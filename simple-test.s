	.text
	.file	"simple-test.ll"
	.globl	_start                          ; -- Begin function _start
	.p2align	1
	.type	_start,@function
_start:                                 ; @_start
	.cfi_startproc
; %bb.0:                                ; %entry
	bra	.LBB0_1
.LBB0_1:                                ; %loop
                                        ; =>This Inner Loop Header: Depth=1
	bra	.LBB0_1
.Lfunc_end0:
	.size	_start, .Lfunc_end0-_start
	.cfi_endproc
                                        ; -- End function
	.globl	rust_eh_personality             ; -- Begin function rust_eh_personality
	.p2align	1
	.type	rust_eh_personality,@function
rust_eh_personality:                    ; @rust_eh_personality
	.cfi_startproc
; %bb.0:                                ; %entry
	rts
.Lfunc_end1:
	.size	rust_eh_personality, .Lfunc_end1-rust_eh_personality
	.cfi_endproc
                                        ; -- End function
	.globl	panic                           ; -- Begin function panic
	.p2align	1
	.type	panic,@function
panic:                                  ; @panic
	.cfi_startproc
; %bb.0:                                ; %entry
	bra	.LBB2_1
.LBB2_1:                                ; %panic_loop
                                        ; =>This Inner Loop Header: Depth=1
	bra	.LBB2_1
.Lfunc_end2:
	.size	panic, .Lfunc_end2-panic
	.cfi_endproc
                                        ; -- End function
	.section	".note.GNU-stack","",@progbits
	.addrsig
