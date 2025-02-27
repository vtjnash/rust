//! Checking that constant values used in types can be successfully evaluated.
//!
//! For concrete constants, this is fairly simple as we can just try and evaluate it.
//!
//! When dealing with polymorphic constants, for example `std::mem::size_of::<T>() - 1`,
//! this is not as easy.
//!
//! In this case we try to build an abstract representation of this constant using
//! `thir_abstract_const` which can then be checked for structural equality with other
//! generic constants mentioned in the `caller_bounds` of the current environment.
use rustc_errors::ErrorGuaranteed;
use rustc_hir::def::DefKind;
use rustc_index::vec::IndexVec;
use rustc_infer::infer::InferCtxt;
use rustc_middle::mir;
use rustc_middle::mir::interpret::{
    ConstValue, ErrorHandled, LitToConstError, LitToConstInput, Scalar,
};
use rustc_middle::thir;
use rustc_middle::thir::abstract_const::{self, Node, NodeId, NotConstEvaluatable};
use rustc_middle::ty::subst::{Subst, SubstsRef};
use rustc_middle::ty::{self, DelaySpanBugEmitted, TyCtxt, TypeFoldable};
use rustc_session::lint;
use rustc_span::def_id::LocalDefId;
use rustc_span::Span;

use std::cmp;
use std::iter;
use std::ops::ControlFlow;

/// Check if a given constant can be evaluated.
#[instrument(skip(infcx), level = "debug")]
pub fn is_const_evaluatable<'cx, 'tcx>(
    infcx: &InferCtxt<'cx, 'tcx>,
    uv: ty::Unevaluated<'tcx, ()>,
    param_env: ty::ParamEnv<'tcx>,
    span: Span,
) -> Result<(), NotConstEvaluatable> {
    let tcx = infcx.tcx;

    if tcx.features().generic_const_exprs {
        match AbstractConst::new(tcx, uv)? {
            // We are looking at a generic abstract constant.
            Some(ct) => {
                if satisfied_from_param_env(tcx, ct, param_env)? {
                    return Ok(());
                }

                // We were unable to unify the abstract constant with
                // a constant found in the caller bounds, there are
                // now three possible cases here.
                #[derive(Debug, Copy, Clone, PartialEq, Eq, PartialOrd, Ord)]
                enum FailureKind {
                    /// The abstract const still references an inference
                    /// variable, in this case we return `TooGeneric`.
                    MentionsInfer,
                    /// The abstract const references a generic parameter,
                    /// this means that we emit an error here.
                    MentionsParam,
                    /// The substs are concrete enough that we can simply
                    /// try and evaluate the given constant.
                    Concrete,
                }
                let mut failure_kind = FailureKind::Concrete;
                walk_abstract_const::<!, _>(tcx, ct, |node| match node.root(tcx) {
                    Node::Leaf(leaf) => {
                        if leaf.has_infer_types_or_consts() {
                            failure_kind = FailureKind::MentionsInfer;
                        } else if leaf.has_param_types_or_consts() {
                            failure_kind = cmp::min(failure_kind, FailureKind::MentionsParam);
                        }

                        ControlFlow::CONTINUE
                    }
                    Node::Cast(_, _, ty) => {
                        if ty.has_infer_types_or_consts() {
                            failure_kind = FailureKind::MentionsInfer;
                        } else if ty.has_param_types_or_consts() {
                            failure_kind = cmp::min(failure_kind, FailureKind::MentionsParam);
                        }

                        ControlFlow::CONTINUE
                    }
                    Node::Binop(_, _, _) | Node::UnaryOp(_, _) | Node::FunctionCall(_, _) => {
                        ControlFlow::CONTINUE
                    }
                });

                match failure_kind {
                    FailureKind::MentionsInfer => {
                        return Err(NotConstEvaluatable::MentionsInfer);
                    }
                    FailureKind::MentionsParam => {
                        return Err(NotConstEvaluatable::MentionsParam);
                    }
                    FailureKind::Concrete => {
                        // Dealt with below by the same code which handles this
                        // without the feature gate.
                    }
                }
            }
            None => {
                // If we are dealing with a concrete constant, we can
                // reuse the old code path and try to evaluate
                // the constant.
            }
        }
    }

    let future_compat_lint = || {
        if let Some(local_def_id) = uv.def.did.as_local() {
            infcx.tcx.struct_span_lint_hir(
                lint::builtin::CONST_EVALUATABLE_UNCHECKED,
                infcx.tcx.hir().local_def_id_to_hir_id(local_def_id),
                span,
                |err| {
                    err.build("cannot use constants which depend on generic parameters in types")
                        .emit();
                },
            );
        }
    };

    // FIXME: We should only try to evaluate a given constant here if it is fully concrete
    // as we don't want to allow things like `[u8; std::mem::size_of::<*mut T>()]`.
    //
    // We previously did not check this, so we only emit a future compat warning if
    // const evaluation succeeds and the given constant is still polymorphic for now
    // and hopefully soon change this to an error.
    //
    // See #74595 for more details about this.
    let concrete = infcx.const_eval_resolve(param_env, uv.expand(), Some(span));

    if concrete.is_ok() && uv.substs.has_param_types_or_consts() {
        match infcx.tcx.def_kind(uv.def.did) {
            DefKind::AnonConst | DefKind::InlineConst => {
                let mir_body = infcx.tcx.mir_for_ctfe_opt_const_arg(uv.def);

                if mir_body.is_polymorphic {
                    future_compat_lint();
                }
            }
            _ => future_compat_lint(),
        }
    }

    // If we're evaluating a foreign constant, under a nightly compiler without generic
    // const exprs, AND it would've passed if that expression had been evaluated with
    // generic const exprs, then suggest using generic const exprs.
    if concrete.is_err()
        && tcx.sess.is_nightly_build()
        && !uv.def.did.is_local()
        && !tcx.features().generic_const_exprs
        && let Ok(Some(ct)) = AbstractConst::new(tcx, uv)
        && satisfied_from_param_env(tcx, ct, param_env) == Ok(true)
    {
        tcx.sess
            .struct_span_fatal(
                // Slightly better span than just using `span` alone
                if span == rustc_span::DUMMY_SP { tcx.def_span(uv.def.did) } else { span },
                "failed to evaluate generic const expression",
            )
            .note("the crate this constant originates from uses `#![feature(generic_const_exprs)]`")
            .span_suggestion_verbose(
                rustc_span::DUMMY_SP,
                "consider enabling this feature",
                "#![feature(generic_const_exprs)]\n".to_string(),
                rustc_errors::Applicability::MaybeIncorrect,
            )
            .emit()
    }

    debug!(?concrete, "is_const_evaluatable");
    match concrete {
        Err(ErrorHandled::TooGeneric) => Err(match uv.has_infer_types_or_consts() {
            true => NotConstEvaluatable::MentionsInfer,
            false => NotConstEvaluatable::MentionsParam,
        }),
        Err(ErrorHandled::Linted) => {
            let reported =
                infcx.tcx.sess.delay_span_bug(span, "constant in type had error reported as lint");
            Err(NotConstEvaluatable::Error(reported))
        }
        Err(ErrorHandled::Reported(e)) => Err(NotConstEvaluatable::Error(e)),
        Ok(_) => Ok(()),
    }
}

#[instrument(skip(tcx), level = "debug")]
fn satisfied_from_param_env<'tcx>(
    tcx: TyCtxt<'tcx>,
    ct: AbstractConst<'tcx>,
    param_env: ty::ParamEnv<'tcx>,
) -> Result<bool, NotConstEvaluatable> {
    for pred in param_env.caller_bounds() {
        match pred.kind().skip_binder() {
            ty::PredicateKind::ConstEvaluatable(uv) => {
                if let Some(b_ct) = AbstractConst::new(tcx, uv)? {
                    let const_unify_ctxt = ConstUnifyCtxt { tcx, param_env };

                    // Try to unify with each subtree in the AbstractConst to allow for
                    // `N + 1` being const evaluatable even if theres only a `ConstEvaluatable`
                    // predicate for `(N + 1) * 2`
                    let result = walk_abstract_const(tcx, b_ct, |b_ct| {
                        match const_unify_ctxt.try_unify(ct, b_ct) {
                            true => ControlFlow::BREAK,
                            false => ControlFlow::CONTINUE,
                        }
                    });

                    if let ControlFlow::Break(()) = result {
                        debug!("is_const_evaluatable: abstract_const ~~> ok");
                        return Ok(true);
                    }
                }
            }
            _ => {} // don't care
        }
    }

    Ok(false)
}

/// A tree representing an anonymous constant.
///
/// This is only able to represent a subset of `MIR`,
/// and should not leak any information about desugarings.
#[derive(Debug, Clone, Copy)]
pub struct AbstractConst<'tcx> {
    // FIXME: Consider adding something like `IndexSlice`
    // and use this here.
    inner: &'tcx [Node<'tcx>],
    substs: SubstsRef<'tcx>,
}

impl<'tcx> AbstractConst<'tcx> {
    pub fn new(
        tcx: TyCtxt<'tcx>,
        uv: ty::Unevaluated<'tcx, ()>,
    ) -> Result<Option<AbstractConst<'tcx>>, ErrorGuaranteed> {
        let inner = tcx.thir_abstract_const_opt_const_arg(uv.def)?;
        debug!("AbstractConst::new({:?}) = {:?}", uv, inner);
        Ok(inner.map(|inner| AbstractConst { inner, substs: uv.substs }))
    }

    pub fn from_const(
        tcx: TyCtxt<'tcx>,
        ct: ty::Const<'tcx>,
    ) -> Result<Option<AbstractConst<'tcx>>, ErrorGuaranteed> {
        match ct.val() {
            ty::ConstKind::Unevaluated(uv) => AbstractConst::new(tcx, uv.shrink()),
            ty::ConstKind::Error(DelaySpanBugEmitted { reported, .. }) => Err(reported),
            _ => Ok(None),
        }
    }

    #[inline]
    pub fn subtree(self, node: NodeId) -> AbstractConst<'tcx> {
        AbstractConst { inner: &self.inner[..=node.index()], substs: self.substs }
    }

    #[inline]
    pub fn root(self, tcx: TyCtxt<'tcx>) -> Node<'tcx> {
        let node = self.inner.last().copied().unwrap();
        match node {
            Node::Leaf(leaf) => Node::Leaf(leaf.subst(tcx, self.substs)),
            Node::Cast(kind, operand, ty) => Node::Cast(kind, operand, ty.subst(tcx, self.substs)),
            // Don't perform substitution on the following as they can't directly contain generic params
            Node::Binop(_, _, _) | Node::UnaryOp(_, _) | Node::FunctionCall(_, _) => node,
        }
    }
}

struct AbstractConstBuilder<'a, 'tcx> {
    tcx: TyCtxt<'tcx>,
    body_id: thir::ExprId,
    body: &'a thir::Thir<'tcx>,
    /// The current WIP node tree.
    nodes: IndexVec<NodeId, Node<'tcx>>,
}

impl<'a, 'tcx> AbstractConstBuilder<'a, 'tcx> {
    fn root_span(&self) -> Span {
        self.body.exprs[self.body_id].span
    }

    fn error(&mut self, span: Span, msg: &str) -> Result<!, ErrorGuaranteed> {
        let reported = self
            .tcx
            .sess
            .struct_span_err(self.root_span(), "overly complex generic constant")
            .span_label(span, msg)
            .help("consider moving this anonymous constant into a `const` function")
            .emit();

        Err(reported)
    }
    fn maybe_supported_error(&mut self, span: Span, msg: &str) -> Result<!, ErrorGuaranteed> {
        let reported = self
            .tcx
            .sess
            .struct_span_err(self.root_span(), "overly complex generic constant")
            .span_label(span, msg)
            .help("consider moving this anonymous constant into a `const` function")
            .note("this operation may be supported in the future")
            .emit();

        Err(reported)
    }

    #[instrument(skip(tcx, body, body_id), level = "debug")]
    fn new(
        tcx: TyCtxt<'tcx>,
        (body, body_id): (&'a thir::Thir<'tcx>, thir::ExprId),
    ) -> Result<Option<AbstractConstBuilder<'a, 'tcx>>, ErrorGuaranteed> {
        let builder = AbstractConstBuilder { tcx, body_id, body, nodes: IndexVec::new() };

        struct IsThirPolymorphic<'a, 'tcx> {
            is_poly: bool,
            thir: &'a thir::Thir<'tcx>,
        }

        use crate::rustc_middle::thir::visit::Visitor;
        use thir::visit;

        impl<'a, 'tcx> IsThirPolymorphic<'a, 'tcx> {
            fn expr_is_poly(&mut self, expr: &thir::Expr<'tcx>) -> bool {
                if expr.ty.has_param_types_or_consts() {
                    return true;
                }

                match expr.kind {
                    thir::ExprKind::NamedConst { substs, .. } => substs.has_param_types_or_consts(),
                    thir::ExprKind::ConstParam { .. } => true,
                    thir::ExprKind::Repeat { value, count } => {
                        self.visit_expr(&self.thir()[value]);
                        count.has_param_types_or_consts()
                    }
                    _ => false,
                }
            }

            fn pat_is_poly(&mut self, pat: &thir::Pat<'tcx>) -> bool {
                if pat.ty.has_param_types_or_consts() {
                    return true;
                }

                match pat.kind.as_ref() {
                    thir::PatKind::Constant { value } => value.has_param_types_or_consts(),
                    thir::PatKind::Range(thir::PatRange { lo, hi, .. }) => {
                        lo.has_param_types_or_consts() || hi.has_param_types_or_consts()
                    }
                    _ => false,
                }
            }
        }

        impl<'a, 'tcx> visit::Visitor<'a, 'tcx> for IsThirPolymorphic<'a, 'tcx> {
            fn thir(&self) -> &'a thir::Thir<'tcx> {
                &self.thir
            }

            #[instrument(skip(self), level = "debug")]
            fn visit_expr(&mut self, expr: &thir::Expr<'tcx>) {
                self.is_poly |= self.expr_is_poly(expr);
                if !self.is_poly {
                    visit::walk_expr(self, expr)
                }
            }

            #[instrument(skip(self), level = "debug")]
            fn visit_pat(&mut self, pat: &thir::Pat<'tcx>) {
                self.is_poly |= self.pat_is_poly(pat);
                if !self.is_poly {
                    visit::walk_pat(self, pat);
                }
            }
        }

        let mut is_poly_vis = IsThirPolymorphic { is_poly: false, thir: body };
        visit::walk_expr(&mut is_poly_vis, &body[body_id]);
        debug!("AbstractConstBuilder: is_poly={}", is_poly_vis.is_poly);
        if !is_poly_vis.is_poly {
            return Ok(None);
        }

        Ok(Some(builder))
    }

    /// We do not allow all binary operations in abstract consts, so filter disallowed ones.
    fn check_binop(op: mir::BinOp) -> bool {
        use mir::BinOp::*;
        match op {
            Add | Sub | Mul | Div | Rem | BitXor | BitAnd | BitOr | Shl | Shr | Eq | Lt | Le
            | Ne | Ge | Gt => true,
            Offset => false,
        }
    }

    /// While we currently allow all unary operations, we still want to explicitly guard against
    /// future changes here.
    fn check_unop(op: mir::UnOp) -> bool {
        use mir::UnOp::*;
        match op {
            Not | Neg => true,
        }
    }

    /// Builds the abstract const by walking the thir and bailing out when
    /// encountering an unsupported operation.
    fn build(mut self) -> Result<&'tcx [Node<'tcx>], ErrorGuaranteed> {
        debug!("Abstractconstbuilder::build: body={:?}", &*self.body);
        self.recurse_build(self.body_id)?;

        for n in self.nodes.iter() {
            if let Node::Leaf(ct) = n {
                if let ty::ConstKind::Unevaluated(ct) = ct.val() {
                    // `AbstractConst`s should not contain any promoteds as they require references which
                    // are not allowed.
                    assert_eq!(ct.promoted, None);
                }
            }
        }

        Ok(self.tcx.arena.alloc_from_iter(self.nodes.into_iter()))
    }

    fn recurse_build(&mut self, node: thir::ExprId) -> Result<NodeId, ErrorGuaranteed> {
        use thir::ExprKind;
        let node = &self.body.exprs[node];
        Ok(match &node.kind {
            // I dont know if handling of these 3 is correct
            &ExprKind::Scope { value, .. } => self.recurse_build(value)?,
            &ExprKind::PlaceTypeAscription { source, .. }
            | &ExprKind::ValueTypeAscription { source, .. } => self.recurse_build(source)?,
            &ExprKind::Literal { lit, neg} => {
                let sp = node.span;
                let constant =
                    match self.tcx.at(sp).lit_to_const(LitToConstInput { lit: &lit.node, ty: node.ty, neg }) {
                        Ok(c) => c,
                        Err(LitToConstError::Reported) => {
                            self.tcx.const_error(node.ty)
                        }
                        Err(LitToConstError::TypeError) => {
                            bug!("encountered type error in lit_to_const")
                        }
                    };

                self.nodes.push(Node::Leaf(constant))
            }
            &ExprKind::NonHirLiteral { lit , user_ty: _} => {
                // FIXME Construct a Valtree from this ScalarInt when introducing Valtrees
                let const_value = ConstValue::Scalar(Scalar::Int(lit));
                self.nodes.push(Node::Leaf(ty::Const::from_value(self.tcx, const_value, node.ty)))
            }
            &ExprKind::NamedConst { def_id, substs, user_ty: _ } => {
                let uneval = ty::Unevaluated::new(ty::WithOptConstParam::unknown(def_id), substs);

                let constant = self.tcx.mk_const(ty::ConstS {
                                val: ty::ConstKind::Unevaluated(uneval),
                                ty: node.ty,
                            });

                self.nodes.push(Node::Leaf(constant))
            }

            ExprKind::ConstParam {param, ..} => {
                let const_param = self.tcx.mk_const(ty::ConstS {
                        val: ty::ConstKind::Param(*param),
                        ty: node.ty,
                    });
                self.nodes.push(Node::Leaf(const_param))
            }

            ExprKind::Call { fun, args, .. } => {
                let fun = self.recurse_build(*fun)?;

                let mut new_args = Vec::<NodeId>::with_capacity(args.len());
                for &id in args.iter() {
                    new_args.push(self.recurse_build(id)?);
                }
                let new_args = self.tcx.arena.alloc_slice(&new_args);
                self.nodes.push(Node::FunctionCall(fun, new_args))
            }
            &ExprKind::Binary { op, lhs, rhs } if Self::check_binop(op) => {
                let lhs = self.recurse_build(lhs)?;
                let rhs = self.recurse_build(rhs)?;
                self.nodes.push(Node::Binop(op, lhs, rhs))
            }
            &ExprKind::Unary { op, arg } if Self::check_unop(op) => {
                let arg = self.recurse_build(arg)?;
                self.nodes.push(Node::UnaryOp(op, arg))
            }
            // This is necessary so that the following compiles:
            //
            // ```
            // fn foo<const N: usize>(a: [(); N + 1]) {
            //     bar::<{ N + 1 }>();
            // }
            // ```
            ExprKind::Block { body: thir::Block { stmts: box [], expr: Some(e), .. } } => {
                self.recurse_build(*e)?
            }
            // `ExprKind::Use` happens when a `hir::ExprKind::Cast` is a
            // "coercion cast" i.e. using a coercion or is a no-op.
            // This is important so that `N as usize as usize` doesnt unify with `N as usize`. (untested)
            &ExprKind::Use { source } => {
                let arg = self.recurse_build(source)?;
                self.nodes.push(Node::Cast(abstract_const::CastKind::Use, arg, node.ty))
            }
            &ExprKind::Cast { source } => {
                let arg = self.recurse_build(source)?;
                self.nodes.push(Node::Cast(abstract_const::CastKind::As, arg, node.ty))
            }
            ExprKind::Borrow{ arg, ..} => {
                let arg_node = &self.body.exprs[*arg];

                // Skip reborrows for now until we allow Deref/Borrow/AddressOf
                // expressions.
                // FIXME(generic_const_exprs): Verify/explain why this is sound
                if let ExprKind::Deref {arg} = arg_node.kind {
                    self.recurse_build(arg)?
                } else {
                    self.maybe_supported_error(
                        node.span,
                        "borrowing is not supported in generic constants",
                    )?
                }
            }
            // FIXME(generic_const_exprs): We may want to support these.
            ExprKind::AddressOf { .. } | ExprKind::Deref {..}=> self.maybe_supported_error(
                node.span,
                "dereferencing or taking the address is not supported in generic constants",
            )?,
            ExprKind::Repeat { .. } | ExprKind::Array { .. } =>  self.maybe_supported_error(
                node.span,
                "array construction is not supported in generic constants",
            )?,
            ExprKind::Block { .. } => self.maybe_supported_error(
                node.span,
                "blocks are not supported in generic constant",
            )?,
            ExprKind::NeverToAny { .. } => self.maybe_supported_error(
                node.span,
                "converting nevers to any is not supported in generic constant",
            )?,
            ExprKind::Tuple { .. } => self.maybe_supported_error(
                node.span,
                "tuple construction is not supported in generic constants",
            )?,
            ExprKind::Index { .. } => self.maybe_supported_error(
                node.span,
                "indexing is not supported in generic constant",
            )?,
            ExprKind::Field { .. } => self.maybe_supported_error(
                node.span,
                "field access is not supported in generic constant",
            )?,
            ExprKind::ConstBlock { .. } => self.maybe_supported_error(
                node.span,
                "const blocks are not supported in generic constant",
            )?,
            ExprKind::Adt(_) => self.maybe_supported_error(
                node.span,
                "struct/enum construction is not supported in generic constants",
            )?,
            // dont know if this is correct
            ExprKind::Pointer { .. } =>
                self.error(node.span, "pointer casts are not allowed in generic constants")?,
            ExprKind::Yield { .. } =>
                self.error(node.span, "generator control flow is not allowed in generic constants")?,
            ExprKind::Continue { .. } | ExprKind::Break { .. } | ExprKind::Loop { .. } => self
                .error(
                    node.span,
                    "loops and loop control flow are not supported in generic constants",
                )?,
            ExprKind::Box { .. } =>
                self.error(node.span, "allocations are not allowed in generic constants")?,

            ExprKind::Unary { .. } => unreachable!(),
            // we handle valid unary/binary ops above
            ExprKind::Binary { .. } =>
                self.error(node.span, "unsupported binary operation in generic constants")?,
            ExprKind::LogicalOp { .. } =>
                self.error(node.span, "unsupported operation in generic constants, short-circuiting operations would imply control flow")?,
            ExprKind::Assign { .. } | ExprKind::AssignOp { .. } => {
                self.error(node.span, "assignment is not supported in generic constants")?
            }
            ExprKind::Closure { .. } | ExprKind::Return { .. } => self.error(
                node.span,
                "closures and function keywords are not supported in generic constants",
            )?,
            // let expressions imply control flow
            ExprKind::Match { .. } | ExprKind::If { .. } | ExprKind::Let { .. } =>
                self.error(node.span, "control flow is not supported in generic constants")?,
            ExprKind::InlineAsm { .. } => {
                self.error(node.span, "assembly is not supported in generic constants")?
            }

            // we dont permit let stmts so `VarRef` and `UpvarRef` cant happen
            ExprKind::VarRef { .. }
            | ExprKind::UpvarRef { .. }
            | ExprKind::StaticRef { .. }
            | ExprKind::ThreadLocalRef(_) => {
                self.error(node.span, "unsupported operation in generic constant")?
            }
        })
    }
}

/// Builds an abstract const, do not use this directly, but use `AbstractConst::new` instead.
pub(super) fn thir_abstract_const<'tcx>(
    tcx: TyCtxt<'tcx>,
    def: ty::WithOptConstParam<LocalDefId>,
) -> Result<Option<&'tcx [thir::abstract_const::Node<'tcx>]>, ErrorGuaranteed> {
    if tcx.features().generic_const_exprs {
        match tcx.def_kind(def.did) {
            // FIXME(generic_const_exprs): We currently only do this for anonymous constants,
            // meaning that we do not look into associated constants. I(@lcnr) am not yet sure whether
            // we want to look into them or treat them as opaque projections.
            //
            // Right now we do neither of that and simply always fail to unify them.
            DefKind::AnonConst | DefKind::InlineConst => (),
            _ => return Ok(None),
        }

        let body = tcx.thir_body(def)?;

        AbstractConstBuilder::new(tcx, (&*body.0.borrow(), body.1))?
            .map(AbstractConstBuilder::build)
            .transpose()
    } else {
        Ok(None)
    }
}

pub(super) fn try_unify_abstract_consts<'tcx>(
    tcx: TyCtxt<'tcx>,
    (a, b): (ty::Unevaluated<'tcx, ()>, ty::Unevaluated<'tcx, ()>),
    param_env: ty::ParamEnv<'tcx>,
) -> bool {
    (|| {
        if let Some(a) = AbstractConst::new(tcx, a)? {
            if let Some(b) = AbstractConst::new(tcx, b)? {
                let const_unify_ctxt = ConstUnifyCtxt { tcx, param_env };
                return Ok(const_unify_ctxt.try_unify(a, b));
            }
        }

        Ok(false)
    })()
    .unwrap_or_else(|_: ErrorGuaranteed| true)
    // FIXME(generic_const_exprs): We should instead have this
    // method return the resulting `ty::Const` and return `ConstKind::Error`
    // on `ErrorGuaranteed`.
}

#[instrument(skip(tcx, f), level = "debug")]
pub fn walk_abstract_const<'tcx, R, F>(
    tcx: TyCtxt<'tcx>,
    ct: AbstractConst<'tcx>,
    mut f: F,
) -> ControlFlow<R>
where
    F: FnMut(AbstractConst<'tcx>) -> ControlFlow<R>,
{
    #[instrument(skip(tcx, f), level = "debug")]
    fn recurse<'tcx, R>(
        tcx: TyCtxt<'tcx>,
        ct: AbstractConst<'tcx>,
        f: &mut dyn FnMut(AbstractConst<'tcx>) -> ControlFlow<R>,
    ) -> ControlFlow<R> {
        f(ct)?;
        let root = ct.root(tcx);
        debug!(?root);
        match root {
            Node::Leaf(_) => ControlFlow::CONTINUE,
            Node::Binop(_, l, r) => {
                recurse(tcx, ct.subtree(l), f)?;
                recurse(tcx, ct.subtree(r), f)
            }
            Node::UnaryOp(_, v) => recurse(tcx, ct.subtree(v), f),
            Node::FunctionCall(func, args) => {
                recurse(tcx, ct.subtree(func), f)?;
                args.iter().try_for_each(|&arg| recurse(tcx, ct.subtree(arg), f))
            }
            Node::Cast(_, operand, _) => recurse(tcx, ct.subtree(operand), f),
        }
    }

    recurse(tcx, ct, &mut f)
}

struct ConstUnifyCtxt<'tcx> {
    tcx: TyCtxt<'tcx>,
    param_env: ty::ParamEnv<'tcx>,
}

impl<'tcx> ConstUnifyCtxt<'tcx> {
    // Substitutes generics repeatedly to allow AbstractConsts to unify where a
    // ConstKind::Unevaluated could be turned into an AbstractConst that would unify e.g.
    // Param(N) should unify with Param(T), substs: [Unevaluated("T2", [Unevaluated("T3", [Param(N)])])]
    #[inline]
    #[instrument(skip(self), level = "debug")]
    fn try_replace_substs_in_root(
        &self,
        mut abstr_const: AbstractConst<'tcx>,
    ) -> Option<AbstractConst<'tcx>> {
        while let Node::Leaf(ct) = abstr_const.root(self.tcx) {
            match AbstractConst::from_const(self.tcx, ct) {
                Ok(Some(act)) => abstr_const = act,
                Ok(None) => break,
                Err(_) => return None,
            }
        }

        Some(abstr_const)
    }

    /// Tries to unify two abstract constants using structural equality.
    #[instrument(skip(self), level = "debug")]
    fn try_unify(&self, a: AbstractConst<'tcx>, b: AbstractConst<'tcx>) -> bool {
        let a = if let Some(a) = self.try_replace_substs_in_root(a) {
            a
        } else {
            return true;
        };

        let b = if let Some(b) = self.try_replace_substs_in_root(b) {
            b
        } else {
            return true;
        };

        let a_root = a.root(self.tcx);
        let b_root = b.root(self.tcx);
        debug!(?a_root, ?b_root);

        match (a_root, b_root) {
            (Node::Leaf(a_ct), Node::Leaf(b_ct)) => {
                let a_ct = a_ct.eval(self.tcx, self.param_env);
                debug!("a_ct evaluated: {:?}", a_ct);
                let b_ct = b_ct.eval(self.tcx, self.param_env);
                debug!("b_ct evaluated: {:?}", b_ct);

                if a_ct.ty() != b_ct.ty() {
                    return false;
                }

                match (a_ct.val(), b_ct.val()) {
                    // We can just unify errors with everything to reduce the amount of
                    // emitted errors here.
                    (ty::ConstKind::Error(_), _) | (_, ty::ConstKind::Error(_)) => true,
                    (ty::ConstKind::Param(a_param), ty::ConstKind::Param(b_param)) => {
                        a_param == b_param
                    }
                    (ty::ConstKind::Value(a_val), ty::ConstKind::Value(b_val)) => a_val == b_val,
                    // If we have `fn a<const N: usize>() -> [u8; N + 1]` and `fn b<const M: usize>() -> [u8; 1 + M]`
                    // we do not want to use `assert_eq!(a(), b())` to infer that `N` and `M` have to be `1`. This
                    // means that we only allow inference variables if they are equal.
                    (ty::ConstKind::Infer(a_val), ty::ConstKind::Infer(b_val)) => a_val == b_val,
                    // We expand generic anonymous constants at the start of this function, so this
                    // branch should only be taking when dealing with associated constants, at
                    // which point directly comparing them seems like the desired behavior.
                    //
                    // FIXME(generic_const_exprs): This isn't actually the case.
                    // We also take this branch for concrete anonymous constants and
                    // expand generic anonymous constants with concrete substs.
                    (ty::ConstKind::Unevaluated(a_uv), ty::ConstKind::Unevaluated(b_uv)) => {
                        a_uv == b_uv
                    }
                    // FIXME(generic_const_exprs): We may want to either actually try
                    // to evaluate `a_ct` and `b_ct` if they are are fully concrete or something like
                    // this, for now we just return false here.
                    _ => false,
                }
            }
            (Node::Binop(a_op, al, ar), Node::Binop(b_op, bl, br)) if a_op == b_op => {
                self.try_unify(a.subtree(al), b.subtree(bl))
                    && self.try_unify(a.subtree(ar), b.subtree(br))
            }
            (Node::UnaryOp(a_op, av), Node::UnaryOp(b_op, bv)) if a_op == b_op => {
                self.try_unify(a.subtree(av), b.subtree(bv))
            }
            (Node::FunctionCall(a_f, a_args), Node::FunctionCall(b_f, b_args))
                if a_args.len() == b_args.len() =>
            {
                self.try_unify(a.subtree(a_f), b.subtree(b_f))
                    && iter::zip(a_args, b_args)
                        .all(|(&an, &bn)| self.try_unify(a.subtree(an), b.subtree(bn)))
            }
            (Node::Cast(a_kind, a_operand, a_ty), Node::Cast(b_kind, b_operand, b_ty))
                if (a_ty == b_ty) && (a_kind == b_kind) =>
            {
                self.try_unify(a.subtree(a_operand), b.subtree(b_operand))
            }
            // use this over `_ => false` to make adding variants to `Node` less error prone
            (Node::Cast(..), _)
            | (Node::FunctionCall(..), _)
            | (Node::UnaryOp(..), _)
            | (Node::Binop(..), _)
            | (Node::Leaf(..), _) => false,
        }
    }
}
