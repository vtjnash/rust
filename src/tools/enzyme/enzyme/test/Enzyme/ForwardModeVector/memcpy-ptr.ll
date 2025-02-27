; NOTE: Assertions have been autogenerated by utils/update_test_checks.py UTC_ARGS: --function-signature --include-generated-funcs
; RUN: %opt < %s %loadEnzyme -enzyme -enzyme-preopt=false -mem2reg -simplifycfg -dce -S | FileCheck %s

; Function Attrs: nounwind
declare void @__enzyme_fwddiff.f64(...)

; Function Attrs: nounwind uwtable
define dso_local void @memcpy_ptr(double** nocapture %dst, double** nocapture readonly %src, i64 %num) #0 {
entry:
  %0 = bitcast double** %dst to i8*
  %1 = bitcast double** %src to i8*
  tail call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 1 %0, i8* align 1 %1, i64 %num, i1 false)
  ret void
}

; Function Attrs: argmemonly nounwind
declare void @llvm.memcpy.p0i8.p0i8.i64(i8* nocapture writeonly, i8* nocapture readonly, i64, i1) #1

; Function Attrs: nounwind uwtable
define dso_local void @dmemcpy_ptr(double** %dst, double** %dstp1, double** %dstp2, double** %dstp3, double** %src, double** %srcp1, double** %srcp2, double** %srcp3, i64 %n) local_unnamed_addr #0 {
entry:
  tail call void (...) @__enzyme_fwddiff.f64(void (double**, double**, i64)* nonnull @memcpy_ptr, metadata !"enzyme_width", i64 3, double** %dst, double** %dstp1, double** %dstp2, double** %dstp3, double** %src, double** %srcp1, double** %srcp2, double** %srcp3, i64 %n) #3
  ret void
}

attributes #0 = { nounwind uwtable }
attributes #1 = { argmemonly nounwind }
attributes #2 = { noinline nounwind uwtable }
attributes #3 = { nounwind }

; CHECK: define {{[^@]+}}@fwddiffe3memcpy_ptr(double** nocapture [[DST:%.*]], [3 x double**] %"dst'", double** nocapture readonly [[SRC:%.*]], [3 x double**] %"src'", i64 [[NUM:%.*]]) 
; CHECK-NEXT:  entry:
; CHECK-NEXT:    [[TMP0:%.*]] = extractvalue [3 x double**] %"dst'", 0
; CHECK-NEXT:    %"'ipc" = bitcast double** [[TMP0]] to i8*
; CHECK-NEXT:    [[TMP2:%.*]] = extractvalue [3 x double**] %"dst'", 1
; CHECK-NEXT:    %"'ipc2" = bitcast double** [[TMP2]] to i8*
; CHECK-NEXT:    [[TMP4:%.*]] = extractvalue [3 x double**] %"dst'", 2
; CHECK-NEXT:    %"'ipc3" = bitcast double** [[TMP4]] to i8*
; CHECK-NEXT:    [[TMP6:%.*]] = bitcast double** [[DST]] to i8*
; CHECK-NEXT:    [[TMP7:%.*]] = extractvalue [3 x double**] %"src'", 0
; CHECK-NEXT:    %"'ipc4" = bitcast double** [[TMP7]] to i8*
; CHECK-NEXT:    [[TMP9:%.*]] = extractvalue [3 x double**] %"src'", 1
; CHECK-NEXT:    %"'ipc5" = bitcast double** [[TMP9]] to i8*
; CHECK-NEXT:    [[TMP11:%.*]] = extractvalue [3 x double**] %"src'", 2
; CHECK-NEXT:    %"'ipc6" = bitcast double** [[TMP11]] to i8*
; CHECK-NEXT:    [[TMP13:%.*]] = bitcast double** [[SRC]] to i8*
; CHECK-NEXT:    tail call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 1 [[TMP6]], i8* align 1 [[TMP13]], i64 [[NUM]], i1 false)
; CHECK-NEXT:    tail call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 1 %"'ipc", i8* align 1 %"'ipc4", i64 [[NUM]], i1 false) 
; CHECK-NEXT:    tail call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 1 %"'ipc2", i8* align 1 %"'ipc5", i64 [[NUM]], i1 false)
; CHECK-NEXT:    tail call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 1 %"'ipc3", i8* align 1 %"'ipc6", i64 [[NUM]], i1 false) 
; CHECK-NEXT:    ret void
;
