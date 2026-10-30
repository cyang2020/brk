==== function 0x100b2afec (size 0x40)
100b2afec:     	adrp	x8, 0x104538000
100b2aff0:     	ldr	x8, [x8, #0xac8]
100b2aff4:     	cmn	x8, #0x1
100b2aff8:     	b.ne	0x100b2b008
100b2affc:     	adrp	x0, 0x104653000
100b2b000:     	add	x0, x0, #0xfb
100b2b004:     	ret
100b2b008:     	stp	x29, x30, [sp, #-0x10]!
100b2b00c:     	mov	x29, sp
100b2b010:     	adrp	x0, 0x104538000
100b2b014:     	add	x0, x0, #0xac8
100b2b018:     	adrp	x1, 0x100b2a000
100b2b01c:     	add	x1, x1, #0xe8c
100b2b020:     	bl	0x1035de348    ;; CALL:stub:_swift_once
100b2b024:     	ldp	x29, x30, [sp], #0x10
100b2b028:     	b	0x100b2affc
