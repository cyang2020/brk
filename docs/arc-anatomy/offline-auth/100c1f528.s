==== function 0x100c1f528 (size 0x8c)
100c1f528:     	ldrb	w8, [x20]
100c1f52c:     	mov	x9, #-0x1c00000000000000 ; =-2017612633061982208
100c1f530:     	mov	w10, #0x7375            ; =29557
100c1f534:     	movk	w10, #0x7265, lsl #16
100c1f538:     	mov	x11, #0x6e69            ; =28265
100c1f53c:     	movk	x11, #0x5567, lsl #16
100c1f540:     	movk	x11, #0x6573, lsl #32
100c1f544:     	movk	x11, #0xef72, lsl #48
100c1f548:     	mov	x12, #0x6177            ; =24951
100c1f54c:     	movk	x12, #0x4573, lsl #16
100c1f550:     	movk	x12, #0x6978, lsl #32
100c1f554:     	movk	x12, #0x7473, lsl #48
100c1f558:     	adrp	x13, 0x103983000
100c1f55c:     	add	x13, x13, #0x560    ;; CSTR:emailChangePendingVerification
100c1f560:     	sub	x13, x13, #0x20
100c1f564:     	orr	x13, x13, #0x8000000000000000
100c1f568:     	mov	x14, #0x12              ; =18
100c1f56c:     	movk	x14, #0xd000, lsl #48
100c1f570:     	orr	x14, x14, #0xc
100c1f574:     	cmp	w8, #0x2
100c1f578:     	csel	x12, x12, x14, eq
100c1f57c:     	csel	x11, x11, x13, eq
100c1f580:     	mov	x13, #0x12              ; =18
100c1f584:     	movk	x13, #0xd000, lsl #48
100c1f588:     	adrp	x14, 0x103983000
100c1f58c:     	add	x14, x14, #0x540    ;; CSTR:finishedOnboarding
100c1f590:     	sub	x14, x14, #0x20
100c1f594:     	orr	x14, x14, #0x8000000000000000
100c1f598:     	cmp	w8, #0x0
100c1f59c:     	csel	x10, x10, x13, eq
100c1f5a0:     	csel	x9, x9, x14, eq
100c1f5a4:     	cmp	w8, #0x1
100c1f5a8:     	csel	x0, x12, x10, gt
100c1f5ac:     	csel	x1, x11, x9, gt
100c1f5b0:     	ret
