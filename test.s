	.text
	.file	"test.c"
	.globl	add_test                        ; -- Begin function add_test
	.p2align	1
	.type	add_test,@function
add_test:                               ; @add_test
; %bb.0:
	link.w	%a6, #0
	move.l	(12,%a6), %d0
	add.l	(8,%a6), %d0
	unlk	%a6
	rts
.Lfunc_end0:
	.size	add_test, .Lfunc_end0-add_test
                                        ; -- End function
	.globl	multiply_test                   ; -- Begin function multiply_test
	.p2align	1
	.type	multiply_test,@function
multiply_test:                          ; @multiply_test
; %bb.0:
	link.w	%a6, #-8
	move.l	(8,%a6), (4,%sp)
	move.l	(12,%a6), (%sp)
	jsr	__mulsi3@PLT
	unlk	%a6
	rts
.Lfunc_end1:
	.size	multiply_test, .Lfunc_end1-multiply_test
                                        ; -- End function
	.globl	branch_test                     ; -- Begin function branch_test
	.p2align	1
	.type	branch_test,@function
branch_test:                            ; @branch_test
; %bb.0:
	link.w	%a6, #0
	unlk	%a6
	rts
.Lfunc_end2:
	.size	branch_test, .Lfunc_end2-branch_test
                                        ; -- End function
	.globl	main                            ; -- Begin function main
	.p2align	1
	.type	main,@function
main:                                   ; @main
; %bb.0:
	link.w	%a6, #0
	move.l	#30, %d0
	unlk	%a6
	rts
.Lfunc_end3:
	.size	main, .Lfunc_end3-main
                                        ; -- End function
	.ident	"clang version 17.0.6 (https://github.com/llvm/llvm-project.git 6009708b4367171ccdbf4b5905cb6a803753fe18)"
	.section	".note.GNU-stack","",@progbits
	.addrsig
