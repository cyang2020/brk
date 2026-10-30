==== function 0x1007e56e0 (size 0x118)
1007e56e0:     	sub	sp, sp, #0x50
1007e56e4:     	stp	x22, x21, [sp, #0x20]
1007e56e8:     	stp	x20, x19, [sp, #0x30]
1007e56ec:     	stp	x29, x30, [sp, #0x40]
1007e56f0:     	add	x29, sp, #0x40
1007e56f4:     	bl	0x10059d594    ;; CALL:fn:10059d594
1007e56f8:     	ldrb	w8, [x0]
1007e56fc:     	cmp	w8, #0x1
1007e5700:     	b.ne	0x1007e57d0
1007e5704:     	bl	0x1035d9848    ;; CALL:stub:_$ss11CommandLineO9argumentsSaySSGvgZ
1007e5708:     	mov	x21, x0
1007e570c:     	mov	x0, #0x2d2d             ; =11565
1007e5710:     	movk	x0, #0x7375, lsl #16
1007e5714:     	movk	x0, #0x7265, lsl #32
1007e5718:     	movk	x0, #0x642d, lsl #48
1007e571c:     	mov	x1, #0x7461             ; =29793
1007e5720:     	movk	x1, #0x2d61, lsl #16
1007e5724:     	movk	x1, #0x6964, lsl #32
1007e5728:     	movk	x1, #0xef72, lsl #48    ;; STR:--user-data-dir
1007e572c:     	mov	x2, x21
1007e5730:     	bl	0x1007e59f8    ;; CALL:fn:1007e59f8
1007e5734:     	mov	x20, x0
1007e5738:     	mov	x19, x1
1007e573c:     	mov	x0, x21
1007e5740:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
1007e5744:     	cbz	x19, 0x1007e57d0
1007e5748:     	mov	x0, x20
1007e574c:     	mov	x1, x19
1007e5750:     	bl	0x1007e5b2c    ;; CALL:fn:1007e5b2c
1007e5754:     	mov	x21, x0
1007e5758:     	mov	x0, x19
1007e575c:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
1007e5760:     	mov	x8, #-0x2000000000000000 ; =-2305843009213693952    ;; STR:
1007e5764:     	stp	xzr, x8, [sp, #0x10]
1007e5768:     	add	x20, sp, #0x10
1007e576c:     	mov	w0, #0x13               ; =19
1007e5770:     	bl	0x1035d9914    ;; CALL:stub:_$ss11_StringGutsV4growyySiF
1007e5774:     	ldr	x0, [sp, #0x18]
1007e5778:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
1007e577c:     	adrp	x8, 0x103974000
1007e5780:     	add	x8, x8, #0x3c0    ;; CSTR:com.dia.instance.
1007e5784:     	sub	x8, x8, #0x20
1007e5788:     	orr	x8, x8, #0x8000000000000000
1007e578c:     	mov	x9, #0x11               ; =17
1007e5790:     	movk	x9, #0xd000, lsl #48
1007e5794:     	stp	x9, x8, [sp, #0x10]
1007e5798:     	str	x21, [sp, #0x8]
1007e579c:     	adrp	x0, 0x10419f000
1007e57a0:     	ldr	x0, [x0, #0x488]
1007e57a4:     	adrp	x1, 0x10419f000
1007e57a8:     	ldr	x1, [x1, #0x4a8]
1007e57ac:     	add	x20, sp, #0x8
1007e57b0:     	bl	0x1035da520    ;; CALL:stub:_$ss23CustomStringConvertibleP11descriptionSSvgTj
1007e57b4:     	mov	x19, x1
1007e57b8:     	add	x20, sp, #0x10
1007e57bc:     	bl	0x1035d7730    ;; CALL:stub:_$sSS6appendyySSF
1007e57c0:     	mov	x0, x19
1007e57c4:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
1007e57c8:     	ldp	x8, x9, [sp, #0x10]
1007e57cc:     	b	0x1007e57d8
1007e57d0:     	mov	x8, #0x0                ; =0
1007e57d4:     	mov	x9, #0x0                ; =0
1007e57d8:     	adrp	x10, 0x104652000
1007e57dc:     	add	x10, x10, #0x180
1007e57e0:     	stp	x8, x9, [x10]
1007e57e4:     	ldp	x29, x30, [sp, #0x40]
1007e57e8:     	ldp	x20, x19, [sp, #0x30]
1007e57ec:     	ldp	x22, x21, [sp, #0x20]
1007e57f0:     	add	sp, sp, #0x50
1007e57f4:     	ret
