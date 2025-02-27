; NOTE: Assertions have been autogenerated by utils/update_test_checks.py UTC_ARGS: --function-signature --include-generated-funcs
; RUN: %opt < %s %loadEnzyme -enzyme -enzyme-preopt=false -mem2reg -S | FileCheck %s

%struct.Gradients = type { {float, float, float}, {float, float, float} }

declare %struct.Gradients @__enzyme_fwddiff({float, float, float} (<4 x float>)*, ...)

define {float, float, float} @square(<4 x float> %x) {
entry:
  %vec = insertelement <4 x float> %x, float 1.0, i32 3
  %sq = fmul <4 x float> %x, %x
  %cb = fmul <4 x float> %sq, %x
  %id = shufflevector <4 x float> %sq, <4 x float> %cb, <4 x i32> <i32 0, i32 1, i32 4, i32 5>
  %res1 = extractelement <4 x float> %id, i32 1
  %res2 = extractelement <4 x float> %id, i32 2
  %res3 = extractelement <4 x float> %id, i32 3
  %agg1 = insertvalue {float, float, float} undef, float %res1, 0
  %agg2 = insertvalue {float, float, float} %agg1, float %res2, 1
  %agg3 = insertvalue {float, float, float} %agg2, float %res3, 2
  ret {float, float, float} %agg3
}

define %struct.Gradients @dsquare(<4 x float> %x) {
entry:
  %call = tail call %struct.Gradients ({float, float, float} (<4 x float>)*, ...) @__enzyme_fwddiff({float, float, float} (<4 x float>)* @square, metadata !"enzyme_width", i64 2, <4 x float> %x, <4 x float> <float 1.0, float 1.0, float 1.0, float 1.0>, <4 x float> <float 1.0, float 1.0, float 1.0, float 1.0>)
  ret %struct.Gradients %call
}

; CHECK: define {{[^@]+}}@fwddiffe2square(<4 x float> [[X:%.*]], [2 x <4 x float>] %"x'") 
; CHECK-NEXT:  entry:
; CHECK-NEXT:    [[SQ:%.*]] = fmul <4 x float> [[X]], [[X]]
; CHECK-NEXT:    [[TMP0:%.*]] = extractvalue [2 x <4 x float>] %"x'", 0
; CHECK-NEXT:    [[TMP1:%.*]] = extractvalue [2 x <4 x float>] %"x'", 0
; CHECK-NEXT:    [[TMP2:%.*]] = fmul fast <4 x float> [[TMP0]], [[X]]
; CHECK-NEXT:    [[TMP3:%.*]] = fmul fast <4 x float> [[TMP1]], [[X]]
; CHECK-NEXT:    [[TMP4:%.*]] = fadd fast <4 x float> [[TMP2]], [[TMP3]]
; CHECK-NEXT:    [[TMP5:%.*]] = insertvalue [2 x <4 x float>] undef, <4 x float> [[TMP4]], 0
; CHECK-NEXT:    [[TMP6:%.*]] = extractvalue [2 x <4 x float>] %"x'", 1
; CHECK-NEXT:    [[TMP7:%.*]] = extractvalue [2 x <4 x float>] %"x'", 1
; CHECK-NEXT:    [[TMP8:%.*]] = fmul fast <4 x float> [[TMP6]], [[X]]
; CHECK-NEXT:    [[TMP9:%.*]] = fmul fast <4 x float> [[TMP7]], [[X]]
; CHECK-NEXT:    [[TMP10:%.*]] = fadd fast <4 x float> [[TMP8]], [[TMP9]]
; CHECK-NEXT:    [[TMP11:%.*]] = insertvalue [2 x <4 x float>] [[TMP5]], <4 x float> [[TMP10]], 1
; CHECK-NEXT:    [[CB:%.*]] = fmul <4 x float> [[SQ]], [[X]]
; CHECK-NEXT:    [[TMP13:%.*]] = extractvalue [2 x <4 x float>] %"x'", 0
; CHECK-NEXT:    [[TMP14:%.*]] = fmul fast <4 x float> [[TMP4]], [[X]]
; CHECK-NEXT:    [[TMP15:%.*]] = fmul fast <4 x float> [[TMP13]], [[SQ]]
; CHECK-NEXT:    [[TMP16:%.*]] = fadd fast <4 x float> [[TMP14]], [[TMP15]]
; CHECK-NEXT:    [[TMP17:%.*]] = insertvalue [2 x <4 x float>] undef, <4 x float> [[TMP16]], 0
; CHECK-NEXT:    [[TMP19:%.*]] = extractvalue [2 x <4 x float>] %"x'", 1
; CHECK-NEXT:    [[TMP20:%.*]] = fmul fast <4 x float> [[TMP10]], [[X]]
; CHECK-NEXT:    [[TMP21:%.*]] = fmul fast <4 x float> [[TMP19]], [[SQ]]
; CHECK-NEXT:    [[TMP22:%.*]] = fadd fast <4 x float> [[TMP20]], [[TMP21]]
; CHECK-NEXT:    [[TMP23:%.*]] = insertvalue [2 x <4 x float>] [[TMP17]], <4 x float> [[TMP22]], 1
; CHECK-NEXT:    %"id'ipsv" = shufflevector <4 x float> [[TMP4]], <4 x float> [[TMP16]], <4 x i32> <i32 0, i32 1, i32 4, i32 5>
; CHECK-NEXT:    [[TMP26:%.*]] = insertvalue [2 x <4 x float>] undef, <4 x float> %"id'ipsv", 0
; CHECK-NEXT:    %"id'ipsv1" = shufflevector <4 x float> [[TMP10]], <4 x float> [[TMP22]], <4 x i32> <i32 0, i32 1, i32 4, i32 5>
; CHECK-NEXT:    [[TMP29:%.*]] = insertvalue [2 x <4 x float>] [[TMP26]], <4 x float> %"id'ipsv1", 1
; CHECK-NEXT:    [[ID:%.*]] = shufflevector <4 x float> [[SQ]], <4 x float> [[CB]], <4 x i32> <i32 0, i32 1, i32 4, i32 5>
; CHECK-NEXT:    %"res1'ipee" = extractelement <4 x float> %"id'ipsv", i32 1
; CHECK-NEXT:    [[TMP31:%.*]] = insertvalue [2 x float] undef, float %"res1'ipee", 0
; CHECK-NEXT:    %"res1'ipee2" = extractelement <4 x float> %"id'ipsv1", i32 1
; CHECK-NEXT:    [[TMP33:%.*]] = insertvalue [2 x float] [[TMP31]], float %"res1'ipee2", 1
; CHECK-NEXT:    [[RES1:%.*]] = extractelement <4 x float> [[ID]], i32 1
; CHECK-NEXT:    %"res2'ipee" = extractelement <4 x float> %"id'ipsv", i32 2
; CHECK-NEXT:    [[TMP35:%.*]] = insertvalue [2 x float] undef, float %"res2'ipee", 0
; CHECK-NEXT:    %"res2'ipee3" = extractelement <4 x float> %"id'ipsv1", i32 2
; CHECK-NEXT:    [[TMP37:%.*]] = insertvalue [2 x float] [[TMP35]], float %"res2'ipee3", 1
; CHECK-NEXT:    [[RES2:%.*]] = extractelement <4 x float> [[ID]], i32 2
; CHECK-NEXT:    %"res3'ipee" = extractelement <4 x float> %"id'ipsv", i32 3
; CHECK-NEXT:    [[TMP39:%.*]] = insertvalue [2 x float] undef, float %"res3'ipee", 0
; CHECK-NEXT:    %"res3'ipee4" = extractelement <4 x float> %"id'ipsv1", i32 3
; CHECK-NEXT:    [[TMP41:%.*]] = insertvalue [2 x float] [[TMP39]], float %"res3'ipee4", 1
; CHECK-NEXT:    [[RES3:%.*]] = extractelement <4 x float> [[ID]], i32 3
; CHECK-NEXT:    %"agg1'ipiv" = insertvalue { float, float, float } zeroinitializer, float %"res1'ipee", 0
; CHECK-NEXT:    [[TMP43:%.*]] = insertvalue [2 x { float, float, float }] undef, { float, float, float } %"agg1'ipiv", 0
; CHECK-NEXT:    %"agg1'ipiv5" = insertvalue { float, float, float } zeroinitializer, float %"res1'ipee2", 0
; CHECK-NEXT:    [[TMP45:%.*]] = insertvalue [2 x { float, float, float }] [[TMP43]], { float, float, float } %"agg1'ipiv5", 1
; CHECK-NEXT:    [[AGG1:%.*]] = insertvalue { float, float, float } undef, float [[RES1]], 0
; CHECK-NEXT:    %"agg2'ipiv" = insertvalue { float, float, float } %"agg1'ipiv", float %"res2'ipee", 1
; CHECK-NEXT:    [[TMP48:%.*]] = insertvalue [2 x { float, float, float }] undef, { float, float, float } %"agg2'ipiv", 0
; CHECK-NEXT:    %"agg2'ipiv6" = insertvalue { float, float, float } %"agg1'ipiv5", float %"res2'ipee3", 1
; CHECK-NEXT:    [[TMP51:%.*]] = insertvalue [2 x { float, float, float }] [[TMP48]], { float, float, float } %"agg2'ipiv6", 1
; CHECK-NEXT:    [[AGG2:%.*]] = insertvalue { float, float, float } [[AGG1]], float [[RES2]], 1
; CHECK-NEXT:    %"agg3'ipiv" = insertvalue { float, float, float } %"agg2'ipiv", float %"res3'ipee", 2
; CHECK-NEXT:    [[TMP54:%.*]] = insertvalue [2 x { float, float, float }] undef, { float, float, float } %"agg3'ipiv", 0
; CHECK-NEXT:    %"agg3'ipiv7" = insertvalue { float, float, float } %"agg2'ipiv6", float %"res3'ipee4", 2
; CHECK-NEXT:    [[TMP57:%.*]] = insertvalue [2 x { float, float, float }] [[TMP54]], { float, float, float } %"agg3'ipiv7", 1
; CHECK-NEXT:    ret [2 x { float, float, float }] [[TMP57]]
;
