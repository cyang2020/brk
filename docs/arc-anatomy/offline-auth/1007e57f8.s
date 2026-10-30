==== function 0x1007e57f8 (size 0x40)
1007e57f8:     	adrp	x8, 0x10451f000
1007e57fc:     	ldr	x8, [x8, #0x2c0]
1007e5800:     	cmn	x8, #0x1
1007e5804:     	b.ne	0x1007e5814
1007e5808:     	adrp	x0, 0x104652000
1007e580c:     	add	x0, x0, #0x180
1007e5810:     	ret
1007e5814:     	stp	x29, x30, [sp, #-0x10]!
1007e5818:     	mov	x29, sp
1007e581c:     	adrp	x0, 0x10451f000
1007e5820:     	add	x0, x0, #0x2c0
1007e5824:     	adrp	x1, 0x1007e5000
1007e5828:     	add	x1, x1, #0x6e0
1007e582c:     	bl	0x1035de348    ;; CALL:stub:_swift_once
1007e5830:     	ldp	x29, x30, [sp], #0x10
1007e5834:     	b	0x1007e5808
