==== function 0x10059d594 (size 0x40)
10059d594:     	adrp	x8, 0x10450c000
10059d598:     	ldr	x8, [x8, #0x998]
10059d59c:     	cmn	x8, #0x1
10059d5a0:     	b.ne	0x10059d5b0
10059d5a4:     	adrp	x0, 0x104652000
10059d5a8:     	add	x0, x0, #0x50
10059d5ac:     	ret
10059d5b0:     	stp	x29, x30, [sp, #-0x10]!
10059d5b4:     	mov	x29, sp
10059d5b8:     	adrp	x0, 0x10450c000
10059d5bc:     	add	x0, x0, #0x998
10059d5c0:     	adrp	x1, 0x10059d000
10059d5c4:     	add	x1, x1, #0x3c0
10059d5c8:     	bl	0x1035de348    ;; CALL:stub:_swift_once
10059d5cc:     	ldp	x29, x30, [sp], #0x10
10059d5d0:     	b	0x10059d5a4
