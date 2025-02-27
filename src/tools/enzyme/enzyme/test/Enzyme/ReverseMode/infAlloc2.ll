; RUN: %opt < %s %loadEnzyme -enzyme -enzyme-preopt=false -mem2reg -gvn -simplifycfg -loop-deletion -simplifycfg -instsimplify -adce -S | FileCheck %s

source_filename = "mem.c"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

@.str = private unnamed_addr constant [4 x i8] c"%f\0A\00", align 1

; Function Attrs: noinline nounwind uwtable
define double @infLoop(double %rho0, i64 %numReg) {
entry:
  br label %for.cond

for.cond:                                         ; preds = %for.end, %entry
  %r.0 = phi i64 [ 0, %entry ], [ %inc7, %for.end ]
  %cmp = icmp ult i64 %r.0, %numReg
  br i1 %cmp, label %for.body, label %for.end8

for.body:                                         ; preds = %for.cond
  %call = call noalias align 16 i8* @calloc(i64 8, i64 1000000) #3
  %i4 = bitcast i8* %call to double*
  store double 1.000000e+00, double* %i4, align 8
  br label %for.cond1

for.cond1:                                        ; preds = %for.body3, %for.body
  %i.0 = phi i64 [ 1, %for.body ], [ %inc, %for.body3 ]
  %cmp2 = icmp ult i64 %i.0, 1000000
  br i1 %cmp2, label %for.body3, label %for.end

for.body3:                                        ; preds = %for.cond1
  %sub = sub i64 %i.0, 1
  %arrayidx4 = getelementptr inbounds double, double* %i4, i64 %sub
  %i10 = load double, double* %arrayidx4, align 8
  %mul = fmul double %i10, %rho0
  %arrayidx5 = getelementptr inbounds double, double* %i4, i64 %i.0
  store double %mul, double* %arrayidx5, align 8
  %inc = add i64 %i.0, 1
  br label %for.cond1, !llvm.loop !4

for.end:                                          ; preds = %for.cond1
  call void @free(i8* %call) #3
  %inc7 = add i64 %r.0, 1
  br label %for.cond, !llvm.loop !6

for.end8:                                         ; preds = %for.cond
  ret double %rho0
}

; Function Attrs: nounwind
declare dso_local noalias i8* @calloc(i64, i64) #1

; Function Attrs: nounwind
declare dso_local void @free(i8*) #1

; Function Attrs: noinline nounwind uwtable
define dso_local i32 @main() #0 {
entry:
  %call = call double @__enzyme_autodiff(i8* bitcast (double (double, i64)* @infLoop to i8*), double 2.000000e+00, i64 10000000)
  %call1 = call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([4 x i8], [4 x i8]* @.str, i64 0, i64 0), double %call)
  ret i32 0
}

declare dso_local i32 @printf(i8*, ...) #2

declare dso_local double @__enzyme_autodiff(i8*, double, i64) #2

attributes #0 = { noinline nounwind uwtable "frame-pointer"="all" "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #1 = { nounwind "frame-pointer"="all" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #2 = { "frame-pointer"="all" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #3 = { nounwind }

!llvm.module.flags = !{!0, !1, !2}
!llvm.ident = !{!3}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 7, !"uwtable", i32 1}
!2 = !{i32 7, !"frame-pointer", i32 2}
!3 = !{!"clang version 14.0.0 (git@github.com:jdoerfert/llvm-project b5b6dc5cda07dc505cc24f6960980780f3d58f3a)"}
!4 = distinct !{!4, !5}
!5 = !{!"llvm.loop.mustprogress"}
!6 = distinct !{!6, !5}

; CHECK: define internal { double } @diffeinfLoop(double %rho0, i64 %numReg, double %differeturn)
; CHECK-NEXT: entry:
; CHECK-NEXT:   br label %for.cond

; CHECK: for.cond:                                         ; preds = %for.end, %entry
; CHECK-NEXT:   %iv = phi i64 [ %iv.next, %for.end ], [ 0, %entry ]
; CHECK-NEXT:   %iv.next = add nuw nsw i64 %iv, 1
; CHECK-NEXT:   %cmp = icmp ne i64 %iv, %numReg
; CHECK-NEXT:   br i1 %cmp, label %for.body, label %remat_enter

; CHECK: for.body:                                         ; preds = %for.cond
; CHECK-NEXT:   %call = call noalias align 16 i8* @calloc(i64 8, i64 1000000)
; CHECK-NEXT:   %i4 = bitcast i8* %call to double*
; CHECK-NEXT:   store double 1.000000e+00, double* %i4, align 8
; CHECK-NEXT:   br label %for.cond1

; CHECK: for.cond1:                                        ; preds = %for.body3, %for.body
; CHECK-NEXT:   %i10 = phi double [ %mul, %for.body3 ], [ 1.000000e+00, %for.body ]
; CHECK-NEXT:   %iv1 = phi i64 [ %iv.next2, %for.body3 ], [ 0, %for.body ]
; CHECK-NEXT:   %iv.next2 = add nuw nsw i64 %iv1, 1
; CHECK-NEXT:   %cmp2 = icmp ne i64 %iv.next2, 1000000
; CHECK-NEXT:   br i1 %cmp2, label %for.body3, label %for.end

; CHECK: for.body3:                                        ; preds = %for.cond1
; CHECK-NEXT:   %mul = fmul double %i10, %rho0
; CHECK-NEXT:   %arrayidx5 = getelementptr inbounds double, double* %i4, i64 %iv.next2
; CHECK-NEXT:   store double %mul, double* %arrayidx5, align 8
; CHECK-NEXT:   br label %for.cond1, !llvm.loop !4

; CHECK: for.end:                                          ; preds = %for.cond1
; CHECK-NEXT:   call void @free(i8* %call)
; CHECK-NEXT:   br label %for.cond, !llvm.loop !6

; CHECK: invertentry: 
; CHECK-NEXT:   %0 = insertvalue { double } undef, double %"rho0'de.0", 0
; CHECK-NEXT:   ret { double } %0

; CHECK: invertfor.cond:                                   ; preds = %invertfor.body, %remat_enter
; CHECK-NEXT:   %"mul'de.0" = phi double [ %"mul'de.1", %invertfor.body ], [ %"mul'de.2", %remat_enter ]
; CHECK-NEXT:   %"i10'de.0" = phi double [ %"i10'de.1", %invertfor.body ], [ %"i10'de.2", %remat_enter ]
; CHECK-NEXT:   %"rho0'de.0" = phi double [ %"rho0'de.1", %invertfor.body ], [ %"rho0'de.2", %remat_enter ]
; CHECK-NEXT:   %1 = icmp eq i64 %"iv'ac.0", 0
; CHECK-NEXT:   br i1 %1, label %invertentry, label %incinvertfor.cond

; CHECK: incinvertfor.cond:
; CHECK-NEXT:   %2 = add nsw i64 %"iv'ac.0", -1
; CHECK-NEXT:   br label %remat_enter

; CHECK: invertfor.body:                                   ; preds = %invertfor.cond1
; CHECK-NEXT:   %"i4'ipc_unwrap" = bitcast i8* %"call'mi" to double*
; CHECK-NEXT:   store double 0.000000e+00, double* %"i4'ipc_unwrap", align 8
; CHECK-NEXT:   tail call void @free(i8* nonnull %"call'mi")
; CHECK-NEXT:   tail call void @free(i8* %remat_call)
; CHECK-NEXT:   br label %invertfor.cond

; CHECK: invertfor.cond1:                                  ; preds = %remat_for.cond_for.cond1, %incinvertfor.cond1
; CHECK-NEXT:   %"mul'de.1" = phi double [ 0.000000e+00, %incinvertfor.cond1 ], [ %"mul'de.2", %remat_for.cond_for.cond1 ]
; CHECK-NEXT:   %"i10'de.1" = phi double [ 0.000000e+00, %incinvertfor.cond1 ], [ %"i10'de.2", %remat_for.cond_for.cond1 ]
; CHECK-NEXT:   %"rho0'de.1" = phi double [ %8, %incinvertfor.cond1 ], [ %"rho0'de.2", %remat_for.cond_for.cond1 ]
; CHECK-NEXT:   %"iv1'ac.0" = phi i64 [ %4, %incinvertfor.cond1 ], [ 999999, %remat_for.cond_for.cond1 ]
; CHECK-NEXT:   %3 = icmp eq i64 %"iv1'ac.0", 0
; CHECK-NEXT:   br i1 %3, label %invertfor.body, label %incinvertfor.cond1

; CHECK: incinvertfor.cond1:                               ; preds = %invertfor.cond1
; CHECK-NEXT:   %4 = add nsw i64 %"iv1'ac.0", -1
; CHECK-NEXT:   %"i4'ipc_unwrap2" = bitcast i8* %"call'mi" to double*
; CHECK-NEXT:   %"arrayidx5'ipg_unwrap" = getelementptr inbounds double, double* %"i4'ipc_unwrap2", i64 %"iv1'ac.0"
; CHECK-NEXT:   %5 = load double, double* %"arrayidx5'ipg_unwrap", align 8
; CHECK-NEXT:   store double 0.000000e+00, double* %"arrayidx5'ipg_unwrap", align 8
; CHECK-NEXT:   %6 = fadd fast double %"mul'de.1", %5
; CHECK-NEXT:   %m0diffei10 = fmul fast double %6, %rho0
; CHECK-NEXT:   %sub_unwrap4 = sub i64 %"iv1'ac.0", 1
; CHECK-NEXT:   %arrayidx4_unwrap5 = getelementptr inbounds double, double* %i4_unwrap, i64 %sub_unwrap4
; CHECK-NEXT:   %i10_unwrap6 = load double, double* %arrayidx4_unwrap5, align 8, !invariant.group !7
; CHECK-NEXT:   %m1differho0 = fmul fast double %6, %i10_unwrap6
; CHECK-NEXT:   %7 = fadd fast double %"i10'de.1", %m0diffei10
; CHECK-NEXT:   %8 = fadd fast double %"rho0'de.1", %m1differho0
; CHECK-NEXT:   %"arrayidx4'ipg_unwrap" = getelementptr inbounds double, double* %"i4'ipc_unwrap2", i64 %sub_unwrap4
; CHECK-NEXT:   %9 = load double, double* %"arrayidx4'ipg_unwrap", align 8
; CHECK-NEXT:   %10 = fadd fast double %9, %7
; CHECK-NEXT:   store double %10, double* %"arrayidx4'ipg_unwrap", align 8
; CHECK-NEXT:   br label %invertfor.cond1

; CHECK: remat_enter:                                      ; preds = %for.cond, %incinvertfor.cond
; CHECK-NEXT:   %"mul'de.2" = phi double [ %"mul'de.0", %incinvertfor.cond ], [ 0.000000e+00, %for.cond ]
; CHECK-NEXT:   %"i10'de.2" = phi double [ %"i10'de.0", %incinvertfor.cond ], [ 0.000000e+00, %for.cond ]
; CHECK-NEXT:   %"rho0'de.2" = phi double [ %"rho0'de.0", %incinvertfor.cond ], [ %differeturn, %for.cond ]
; CHECK-NEXT:   %"iv'ac.0" = phi i64 [ %2, %incinvertfor.cond ], [ %numReg, %for.cond ]
; CHECK-NEXT:   %cmp_unwrap = icmp ne i64 %"iv'ac.0", %numReg
; CHECK-NEXT:   br i1 %cmp_unwrap, label %remat_for.cond_for.body, label %invertfor.cond

; CHECK: remat_for.cond_for.body:                          ; preds = %remat_enter
; CHECK-NEXT:   %remat_call = call noalias align 16 i8* @calloc(i64 8, i64 1000000) 
; CHECK-NEXT:   %"call'mi" = call noalias nonnull align 16 i8* @calloc(i64 8, i64 1000000) 
; CHECK-NEXT:   %i4_unwrap = bitcast i8* %remat_call to double*
; CHECK-NEXT:   store double 1.000000e+00, double* %i4_unwrap, align 8
; CHECK-NEXT:   br label %remat_for.cond_for.cond1

; CHECK: remat_for.cond_for.cond1:                         ; preds = %remat_for.cond_for.body3, %remat_for.cond_for.body
; CHECK-NEXT:   %i10_unwrap = phi double [ %mul_unwrap, %remat_for.cond_for.body3 ], [ 1.000000e+00, %remat_for.cond_for.body ]
; CHECK-NEXT:   %fiv = phi i64 [ %11, %remat_for.cond_for.body3 ], [ 0, %remat_for.cond_for.body ]
; CHECK-NEXT:   %11 = add i64 %fiv, 1
; CHECK-NEXT:   %cmp2_unwrap = icmp ne i64 %11, 1000000
; CHECK-NEXT:   br i1 %cmp2_unwrap, label %remat_for.cond_for.body3, label %invertfor.cond1

; CHECK: remat_for.cond_for.body3:                         ; preds = %remat_for.cond_for.cond1
; CHECK-DAG:    %arrayidx5_unwrap = getelementptr inbounds double, double* %i4_unwrap, i64 %11
; CHECK-DAG:    %mul_unwrap = fmul double %i10_unwrap, %rho0
; CHECK-NEXT:   store double %mul_unwrap, double* %arrayidx5_unwrap, align 8
; CHECK-NEXT:   br label %remat_for.cond_for.cond1
; CHECK-NEXT: }
