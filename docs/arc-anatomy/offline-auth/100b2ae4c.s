==== function 0x100b2ae4c (size 0x40)
100b2ae4c:     	adrp	x8, 0x104538000
100b2ae50:     	ldr	x8, [x8, #0xac0]
100b2ae54:     	cmn	x8, #0x1
100b2ae58:     	b.ne	0x100b2ae68
100b2ae5c:     	adrp	x0, 0x104653000
100b2ae60:     	add	x0, x0, #0xfa
100b2ae64:     	ret
100b2ae68:     	stp	x29, x30, [sp, #-0x10]!
100b2ae6c:     	mov	x29, sp
100b2ae70:     	adrp	x0, 0x104538000
100b2ae74:     	add	x0, x0, #0xac0
100b2ae78:     	adrp	x1, 0x100b2a000
100b2ae7c:     	add	x1, x1, #0xdbc
100b2ae80:     	bl	0x1035de348    ;; CALL:stub:_swift_once
100b2ae84:     	ldp	x29, x30, [sp], #0x10
100b2ae88:     	b	0x100b2ae5c
