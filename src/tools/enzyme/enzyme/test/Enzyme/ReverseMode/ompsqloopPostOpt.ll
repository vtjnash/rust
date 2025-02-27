; RUN: if [ %llvmver -ge 9 ]; then %opt < %s %loadEnzyme -enzyme -enzyme-preopt=false -mem2reg -instsimplify -adce -loop-deletion -correlated-propagation -simplifycfg -adce -simplifycfg -S --enzyme-postopt=1 | FileCheck %s; fi

source_filename = "lulesh.cc"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

%struct.ident_t = type { i32, i32, i32, i32, i8* }

@0 = private unnamed_addr constant [23 x i8] c";unknown;unknown;0;0;;\00", align 1
@1 = private unnamed_addr constant %struct.ident_t { i32 0, i32 514, i32 0, i32 0, i8* getelementptr inbounds ([23 x i8], [23 x i8]* @0, i32 0, i32 0) }, align 8
@2 = private unnamed_addr constant %struct.ident_t { i32 0, i32 2, i32 0, i32 0, i8* getelementptr inbounds ([23 x i8], [23 x i8]* @0, i32 0, i32 0) }, align 8

; Function Attrs: norecurse nounwind uwtable mustprogress
define dso_local i32 @main(i32 %argc, i8** nocapture readnone %argv) local_unnamed_addr #0 {
entry:
  %data = alloca [100 x double], align 16
  %d_data = alloca [100 x double], align 16
  %0 = bitcast [100 x double]* %data to i8*
  %1 = bitcast [100 x double]* %d_data to i8*
  call void @_Z17__enzyme_autodiffPvS_S_m(i8* bitcast (void (double*, i64)* @_ZL16LagrangeLeapFrogPdm to i8*), i8* nonnull %0, i8* nonnull %1, i64 100) #5
  ret i32 0
}

declare dso_local void @_Z17__enzyme_autodiffPvS_S_m(i8*, i8*, i8*, i64) local_unnamed_addr #2

; Function Attrs: inlinehint nounwind uwtable mustprogress
define internal void @_ZL16LagrangeLeapFrogPdm(double* %e_new, i64 %length) #3 {
entry:
  tail call void (%struct.ident_t*, i32, void (i32*, i32*, ...)*, ...) @__kmpc_fork_call(%struct.ident_t* nonnull @2, i32 2, void (i32*, i32*, ...)* bitcast (void (i32*, i32*, i64, double*)* @.omp_outlined. to void (i32*, i32*, ...)*), i64 %length, double* %e_new)
  ret void
}

; Function Attrs: norecurse nounwind uwtable
define internal void @.omp_outlined.(i32* noalias nocapture readonly %.global_tid., i32* noalias nocapture readnone %.bound_tid., i64 %length, double* nocapture nonnull align 8 dereferenceable(8) %tmp) #4 {
entry:
  %.omp.lb = alloca i64, align 8
  %.omp.ub = alloca i64, align 8
  %.omp.stride = alloca i64, align 8
  %.omp.is_last = alloca i32, align 4
  %sub4 = add i64 %length, -1
  %cmp.not = icmp eq i64 %length, 0
  br i1 %cmp.not, label %omp.precond.end, label %omp.precond.then

omp.precond.then:                                 ; preds = %entry
  %0 = bitcast i64* %.omp.lb to i8*
  store i64 0, i64* %.omp.lb, align 8, !tbaa !3
  %1 = bitcast i64* %.omp.ub to i8*
  store i64 %sub4, i64* %.omp.ub, align 8, !tbaa !3
  %2 = bitcast i64* %.omp.stride to i8*
  store i64 1, i64* %.omp.stride, align 8, !tbaa !3
  %3 = bitcast i32* %.omp.is_last to i8*
  store i32 0, i32* %.omp.is_last, align 4, !tbaa !7
  %4 = load i32, i32* %.global_tid., align 4, !tbaa !7
  call void @__kmpc_for_static_init_8u(%struct.ident_t* nonnull @1, i32 %4, i32 34, i32* nonnull %.omp.is_last, i64* nonnull %.omp.lb, i64* nonnull %.omp.ub, i64* nonnull %.omp.stride, i64 1, i64 1)
  %5 = load i64, i64* %.omp.ub, align 8, !tbaa !3
  %cmp6 = icmp ugt i64 %5, %sub4
  %cond = select i1 %cmp6, i64 %sub4, i64 %5
  store i64 %cond, i64* %.omp.ub, align 8, !tbaa !3
  %6 = load i64, i64* %.omp.lb, align 8, !tbaa !3
  %add29 = add i64 %cond, 1
  %cmp730 = icmp ult i64 %6, %add29
  br i1 %cmp730, label %omp.inner.for.body, label %omp.loop.exit

omp.inner.for.body:                               ; preds = %omp.precond.then, %omp.inner.for.body
  %.omp.iv.031 = phi i64 [ %add11, %omp.inner.for.body ], [ %6, %omp.precond.then ]
  %arrayidx = getelementptr inbounds double, double* %tmp, i64 %.omp.iv.031
  %7 = load double, double* %arrayidx, align 8, !tbaa !9
  %call = call double @sqrt(double %7) #5
  store double %call, double* %arrayidx, align 8, !tbaa !9
  %add11 = add nuw i64 %.omp.iv.031, 1
  %8 = load i64, i64* %.omp.ub, align 8, !tbaa !3
  %add = add i64 %8, 1
  %cmp7 = icmp ult i64 %add11, %add
  br i1 %cmp7, label %omp.inner.for.body, label %omp.loop.exit

omp.loop.exit:                                    ; preds = %omp.inner.for.body, %omp.precond.then
  call void @__kmpc_for_static_fini(%struct.ident_t* nonnull @1, i32 %4)
  br label %omp.precond.end

omp.precond.end:                                  ; preds = %omp.loop.exit, %entry
  ret void
}

; Function Attrs: nounwind
declare dso_local void @__kmpc_for_static_init_8u(%struct.ident_t*, i32, i32, i32*, i64*, i64*, i64*, i64, i64) local_unnamed_addr #5

; Function Attrs: nofree nounwind willreturn mustprogress
declare dso_local double @sqrt(double) local_unnamed_addr #6

; Function Attrs: nounwind
declare void @__kmpc_for_static_fini(%struct.ident_t*, i32) local_unnamed_addr #5

; Function Attrs: nounwind
declare !callback !11 void @__kmpc_fork_call(%struct.ident_t*, i32, void (i32*, i32*, ...)*, ...) local_unnamed_addr #5

attributes #0 = { norecurse nounwind uwtable }
attributes #1 = { argmemonly }

!llvm.module.flags = !{!0, !1}
!llvm.ident = !{!2}
!nvvm.annotations = !{}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 7, !"uwtable", i32 1}
!2 = !{!"clang version 13.0.0 (git@github.com:llvm/llvm-project 619bfe8bd23f76b22f0a53fedafbfc8c97a15f12)"}
!3 = !{!4, !4, i64 0}
!4 = !{!"long", !5, i64 0}
!5 = !{!"omnipotent char", !6, i64 0}
!6 = !{!"Simple C++ TBAA"}
!7 = !{!8, !8, i64 0}
!8 = !{!"int", !5, i64 0}
!9 = !{!10, !10, i64 0}
!10 = !{!"double", !5, i64 0}
!11 = !{!12}
!12 = !{i64 2, i64 -1, i64 -1, i1 true}

; CHECK-LABEL: define internal void @augmented_.omp_outlined..1(i32* noalias nocapture readonly %.global_tid., i32* noalias nocapture readnone %.bound_tid., i64 %length, double* nocapture nonnull align 8 dereferenceable(8) %tmp, double* nocapture readnone %"tmp'", double** nocapture readonly %tape)
; CHECK-NOT: call{{.*}}@malloc
; CHECK: }

; CHECK-LABEL: define internal void @diffe.omp_outlined.(i32* noalias nocapture readonly %.global_tid., i32* noalias nocapture readnone %.bound_tid., i64 %length, double* nocapture nonnull readnone align 8 dereferenceable(8) %tmp, double* nocapture %"tmp'", double** nocapture readonly %tapeArg)
; CHECK-NOT: call{{.*}}@free
; CHECK: }
