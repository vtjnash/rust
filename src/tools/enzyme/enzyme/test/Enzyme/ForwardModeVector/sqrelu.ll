; NOTE: Assertions have been autogenerated by utils/update_test_checks.py UTC_ARGS: --function dsqrelu
; RUN: %opt < %s %loadEnzyme -enzyme -enzyme-preopt=false -inline -mem2reg -simplifycfg -adce -S | FileCheck %s

%struct.Gradients = type { double, double }

; Function Attrs: nounwind
declare %struct.Gradients @__enzyme_fwddiff(double (double)*, ...)

; Function Attrs: nounwind readnone uwtable
define dso_local double @sqrelu(double %x) #0 {
entry:
  %cmp = fcmp fast ogt double %x, 0.000000e+00
  br i1 %cmp, label %cond.true, label %cond.end

cond.true:                                        ; preds = %entry
  %0 = tail call fast double @llvm.sin.f64(double %x)
  %mul = fmul fast double %0, %x
  %1 = tail call fast double @llvm.sqrt.f64(double %mul)
  br label %cond.end

cond.end:                                         ; preds = %entry, %cond.true
  %cond = phi double [ %1, %cond.true ], [ 0.000000e+00, %entry ]
  ret double %cond
}

; Function Attrs: nounwind readnone speculatable
declare double @llvm.sin.f64(double) #1

; Function Attrs: nounwind readnone speculatable
declare double @llvm.sqrt.f64(double) #1

; Function Attrs: nounwind uwtable
define dso_local %struct.Gradients @dsqrelu(double %x) local_unnamed_addr #2 {
entry:
  %0 = tail call %struct.Gradients (double (double)*, ...) @__enzyme_fwddiff(double (double)* nonnull @sqrelu, metadata !"enzyme_width", i64 2, double %x, double 1.0, double 1.5)
  ret %struct.Gradients %0
}

attributes #0 = { nounwind readnone uwtable }
attributes #1 = { nounwind readnone speculatable }
attributes #2 = { nounwind uwtable }
attributes #3 = { nounwind }


; CHECK: define dso_local %struct.Gradients @dsqrelu(double [[X:%.*]])
; CHECK-NEXT:  entry:
; CHECK-NEXT:    [[CMP_I:%.*]] = fcmp fast ogt double [[X]], 0.000000e+00
; CHECK-NEXT:    br i1 [[CMP_I]], label [[COND_TRUE_I:%.*]], label [[FWDDIFFE2SQRELU_EXIT:%.*]]
; CHECK:       cond.true.i:
; CHECK-NEXT:    [[TMP0:%.*]] = call fast double @llvm.sin.f64(double [[X]]) 
; CHECK-NEXT:    [[TMP1:%.*]] = call fast double @llvm.cos.f64(double [[X]]) 
; CHECK-NEXT:    [[TMP2:%.*]] = fmul fast double 1.500000e+00, [[TMP1]]
; CHECK-NEXT:    [[MUL_I:%.*]] = fmul fast double [[TMP0]], [[X]]
; CHECK-NEXT:    [[TMP3:%.*]] = fmul fast double [[TMP1]], [[X]]
; CHECK-NEXT:    [[TMP4:%.*]] = fadd fast double [[TMP3]], [[TMP0]]
; CHECK-NEXT:    [[TMP5:%.*]] = fmul fast double [[TMP2]], [[X]]
; CHECK-NEXT:    [[TMP6:%.*]] = fmul fast double 1.500000e+00, [[TMP0]]
; CHECK-NEXT:    [[TMP7:%.*]] = fadd fast double [[TMP5]], [[TMP6]]
; CHECK-NEXT:    [[TMP8:%.*]] = call fast double @llvm.sqrt.f64(double [[MUL_I]])
; CHECK-NEXT:    [[TMP9:%.*]] = fmul fast double 5.000000e-01, [[TMP4]]
; CHECK-NEXT:    [[TMP10:%.*]] = fdiv fast double [[TMP9]], [[TMP8]]
; CHECK-NEXT:    [[TMP11:%.*]] = fcmp fast oeq double [[MUL_I]], 0.000000e+00
; CHECK-NEXT:    [[TMP12:%.*]] = select {{(fast )?}}i1 [[TMP11]], double 0.000000e+00, double [[TMP10]]
; CHECK-NEXT:    [[TMP13:%.*]] = insertvalue [2 x double] undef, double [[TMP12]], 0
; CHECK-NEXT:    [[TMP14:%.*]] = call fast double @llvm.sqrt.f64(double [[MUL_I]]) 
; CHECK-NEXT:    [[TMP15:%.*]] = fmul fast double 5.000000e-01, [[TMP7]]
; CHECK-NEXT:    [[TMP16:%.*]] = fdiv fast double [[TMP15]], [[TMP14]]
; CHECK-NEXT:    [[TMP17:%.*]] = fcmp fast oeq double [[MUL_I]], 0.000000e+00
; CHECK-NEXT:    [[TMP18:%.*]] = select {{(fast )?}}i1 [[TMP17]], double 0.000000e+00, double [[TMP16]]
; CHECK-NEXT:    [[TMP19:%.*]] = insertvalue [2 x double] [[TMP13]], double [[TMP18]], 1
; CHECK-NEXT:    br label [[FWDDIFFE2SQRELU_EXIT]]
; CHECK:       fwddiffe2sqrelu.exit:
; CHECK-NEXT:    [[TMP20:%.*]] = phi {{(fast )?}}[2 x double] [ [[TMP19]], [[COND_TRUE_I]] ], [ zeroinitializer, [[ENTRY:%.*]] ]
; CHECK-NEXT:    [[TMP21:%.*]] = extractvalue [2 x double] [[TMP20]], 0
; CHECK-NEXT:    [[TMP22:%.*]] = insertvalue [[STRUCT_GRADIENTS:%.*]] zeroinitializer, double [[TMP21]], 0
; CHECK-NEXT:    [[TMP23:%.*]] = extractvalue [2 x double] [[TMP20]], 1
; CHECK-NEXT:    [[TMP24:%.*]] = insertvalue [[STRUCT_GRADIENTS]] [[TMP22]], double [[TMP23]], 1
; CHECK-NEXT:    ret [[STRUCT_GRADIENTS]] [[TMP24]]
;
