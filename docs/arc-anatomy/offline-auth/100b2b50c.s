==== function 0x100b2b50c (size 0x40)
100b2b50c:     	adrp	x8, 0x104538000
100b2b510:     	ldr	x8, [x8, #0xb18]
100b2b514:     	cmn	x8, #0x1
100b2b518:     	b.ne	0x100b2b528
100b2b51c:     	adrp	x0, 0x104653000
100b2b520:     	add	x0, x0, #0x111
100b2b524:     	ret
100b2b528:     	stp	x29, x30, [sp, #-0x10]!
100b2b52c:     	mov	x29, sp
100b2b530:     	adrp	x0, 0x104538000
100b2b534:     	add	x0, x0, #0xb18
100b2b538:     	adrp	x1, 0x100b2b000
100b2b53c:     	add	x1, x1, #0x39c
100b2b540:     	bl	0x1035de348    ;; CALL:stub:_swift_once
100b2b544:     	ldp	x29, x30, [sp], #0x10
100b2b548:     	b	0x100b2b51c
