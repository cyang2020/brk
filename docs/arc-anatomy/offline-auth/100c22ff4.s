==== function 0x100c22ff4 (size 0x174)
100c22ff4:     	stp	x22, x21, [sp, #-0x30]!
100c22ff8:     	stp	x20, x19, [sp, #0x10]
100c22ffc:     	stp	x29, x30, [sp, #0x20]
100c23000:     	add	x29, sp, #0x20
100c23004:     	mov	x19, x1
100c23008:     	mov	w8, #0x7375             ; =29557
100c2300c:     	movk	w8, #0x7265, lsl #16
100c23010:     	cmp	x0, x8
100c23014:     	mov	x8, #-0x1c00000000000000 ; =-2017612633061982208    ;; STR:user
100c23018:     	ccmp	x1, x8, #0x0, eq
100c2301c:     	b.eq	0x100c23044
100c23020:     	mov	x20, x0
100c23024:     	mov	w0, #0x7375             ; =29557
100c23028:     	movk	w0, #0x7265, lsl #16
100c2302c:     	mov	x1, #-0x1c00000000000000 ; =-2017612633061982208    ;; STR:user
100c23030:     	mov	x2, x20
100c23034:     	mov	x3, x19
100c23038:     	mov	w4, #0x0                ; =0
100c2303c:     	bl	0x1035da838    ;; CALL:stub:_$ss27_stringCompareWithSmolCheck__9expectingSbs11_StringGutsV_ADs01_G16ComparisonResultOtF
100c23040:     	tbz	w0, #0x0, 0x100c23060
100c23044:     	mov	x0, x19
100c23048:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100c2304c:     	mov	w0, #0x0                ; =0
100c23050:     	ldp	x29, x30, [sp, #0x20]
100c23054:     	ldp	x20, x19, [sp, #0x10]
100c23058:     	ldp	x22, x21, [sp], #0x30
100c2305c:     	ret
100c23060:     	mov	x21, #0x12              ; =18
100c23064:     	movk	x21, #0xd000, lsl #48
100c23068:     	adrp	x8, 0x103983000
100c2306c:     	add	x8, x8, #0x540    ;; CSTR:finishedOnboarding
100c23070:     	sub	x8, x8, #0x20
100c23074:     	orr	x1, x8, #0x8000000000000000
100c23078:     	cmp	x20, x21
100c2307c:     	b.ne	0x100c23088
100c23080:     	cmp	x1, x19
100c23084:     	b.eq	0x100c230a4
100c23088:     	mov	x0, #0x12               ; =18
100c2308c:     	movk	x0, #0xd000, lsl #48
100c23090:     	mov	x2, x20
100c23094:     	mov	x3, x19
100c23098:     	mov	w4, #0x0                ; =0
100c2309c:     	bl	0x1035da838    ;; CALL:stub:_$ss27_stringCompareWithSmolCheck__9expectingSbs11_StringGutsV_ADs01_G16ComparisonResultOtF
100c230a0:     	tbz	w0, #0x0, 0x100c230b4
100c230a4:     	mov	x0, x19
100c230a8:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100c230ac:     	mov	w0, #0x1                ; =1
100c230b0:     	b	0x100c23050
100c230b4:     	mov	x1, #0x6e69             ; =28265
100c230b8:     	movk	x1, #0x5567, lsl #16
100c230bc:     	movk	x1, #0x6573, lsl #32
100c230c0:     	movk	x1, #0xef72, lsl #48
100c230c4:     	mov	x0, #0x6177             ; =24951
100c230c8:     	movk	x0, #0x4573, lsl #16
100c230cc:     	movk	x0, #0x6978, lsl #32
100c230d0:     	movk	x0, #0x7473, lsl #48
100c230d4:     	cmp	x20, x0
100c230d8:     	b.ne	0x100c230e4
100c230dc:     	cmp	x19, x1
100c230e0:     	b.eq	0x100c230f8
100c230e4:     	mov	x2, x20
100c230e8:     	mov	x3, x19
100c230ec:     	mov	w4, #0x0                ; =0
100c230f0:     	bl	0x1035da838    ;; CALL:stub:_$ss27_stringCompareWithSmolCheck__9expectingSbs11_StringGutsV_ADs01_G16ComparisonResultOtF
100c230f4:     	tbz	w0, #0x0, 0x100c23108
100c230f8:     	mov	x0, x19
100c230fc:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100c23100:     	mov	w0, #0x2                ; =2
100c23104:     	b	0x100c23050
100c23108:     	adrp	x8, 0x103983000
100c2310c:     	add	x8, x8, #0x560    ;; CSTR:emailChangePendingVerification
100c23110:     	sub	x8, x8, #0x20
100c23114:     	orr	x1, x8, #0x8000000000000000
100c23118:     	add	x0, x21, #0xc
100c2311c:     	cmp	x20, x0
100c23120:     	b.ne	0x100c2313c
100c23124:     	cmp	x1, x19
100c23128:     	b.ne	0x100c2313c
100c2312c:     	mov	x0, x19
100c23130:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100c23134:     	mov	w0, #0x3                ; =3
100c23138:     	b	0x100c23050
100c2313c:     	mov	x2, x20
100c23140:     	mov	x3, x19
100c23144:     	mov	w4, #0x0                ; =0
100c23148:     	bl	0x1035da838    ;; CALL:stub:_$ss27_stringCompareWithSmolCheck__9expectingSbs11_StringGutsV_ADs01_G16ComparisonResultOtF
100c2314c:     	mov	x20, x0
100c23150:     	mov	x0, x19
100c23154:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100c23158:     	tst	w20, #0x1
100c2315c:     	mov	w8, #0x3                ; =3
100c23160:     	cinc	w0, w8, eq
100c23164:     	b	0x100c23050
