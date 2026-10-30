==== function 0x100003138 (size 0x1b4)
100003138:     	sub	sp, sp, #0x40
10000313c:     	stp	x22, x21, [sp, #0x10]
100003140:     	stp	x20, x19, [sp, #0x20]
100003144:     	stp	x29, x30, [sp, #0x30]
100003148:     	add	x29, sp, #0x30
10000314c:     	bl	0x1035d9848    ;; CALL:stub:_$ss11CommandLineO9argumentsSaySSGvgZ
100003150:     	mov	x19, x0
100003154:     	bl	0x1007f0e28    ;; CALL:fn:1007f0e28
100003158:     	mov	x20, x0
10000315c:     	mov	x21, x1
100003160:     	mov	x0, x19
100003164:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
100003168:     	adrp	x8, 0x104651000
10000316c:     	add	x8, x8, #0x2a8
100003170:     	str	x20, [x8]
100003174:     	strb	w21, [x8, #0x8]
100003178:     	adrp	x0, 0x100003000
10000317c:     	add	x0, x0, #0x2ec
100003180:     	mov	x1, #0x0                ; =0
100003184:     	bl	0x100729d38    ;; CALL:fn:100729d38
100003188:     	adrp	x8, 0x104640000
10000318c:     	add	x8, x8, #0x738
100003190:     	ldr	x0, [x8]
100003194:     	bl	0x1035d7400    ;; CALL:stub:_$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ
100003198:     	mov	x19, x1
10000319c:     	bl	0x1035d75e0    ;; CALL:stub:_$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg
1000031a0:     	mov	x20, x0
1000031a4:     	mov	x0, x19
1000031a8:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
1000031ac:     	adrp	x0, 0x103949000
1000031b0:     	add	x0, x0, #0x330    ;; CSTR:GOOGLE_API_KEY
1000031b4:     	add	x1, x20, #0x20
1000031b8:     	mov	w2, #0x0                ; =0
1000031bc:     	bl	0x1035ddca0    ;; CALL:stub:_setenv
1000031c0:     	mov	x0, x20
1000031c4:     	bl	0x1035de3a8    ;; CALL:stub:_swift_release
1000031c8:     	adrp	x8, 0x104640000
1000031cc:     	add	x8, x8, #0x740
1000031d0:     	ldr	x0, [x8]
1000031d4:     	bl	0x1035d7400    ;; CALL:stub:_$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ
1000031d8:     	mov	x19, x1
1000031dc:     	bl	0x1035d75e0    ;; CALL:stub:_$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg
1000031e0:     	mov	x20, x0
1000031e4:     	mov	x0, x19
1000031e8:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
1000031ec:     	adrp	x0, 0x103949000
1000031f0:     	add	x0, x0, #0x340    ;; CSTR:GOOGLE_DEFAULT_CLIENT_ID
1000031f4:     	add	x1, x20, #0x20
1000031f8:     	mov	w2, #0x0                ; =0
1000031fc:     	bl	0x1035ddca0    ;; CALL:stub:_setenv
100003200:     	mov	x0, x20
100003204:     	bl	0x1035de3a8    ;; CALL:stub:_swift_release
100003208:     	adrp	x8, 0x104640000
10000320c:     	add	x8, x8, #0x748
100003210:     	ldr	x0, [x8]
100003214:     	bl	0x1035d7400    ;; CALL:stub:_$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ
100003218:     	mov	x19, x1
10000321c:     	bl	0x1035d75e0    ;; CALL:stub:_$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg
100003220:     	mov	x20, x0
100003224:     	mov	x0, x19
100003228:     	bl	0x1035ddf40    ;; CALL:stub:_swift_bridgeObjectRelease
10000322c:     	adrp	x0, 0x103949000
100003230:     	add	x0, x0, #0x360    ;; CSTR:GOOGLE_DEFAULT_CLIENT_SECRET
100003234:     	add	x1, x20, #0x20
100003238:     	mov	w2, #0x0                ; =0
10000323c:     	bl	0x1035ddca0    ;; CALL:stub:_setenv
100003240:     	mov	x0, x20
100003244:     	bl	0x1035de3a8    ;; CALL:stub:_swift_release
100003248:     	adrp	x8, 0x104651000
10000324c:     	strb	wzr, [x8, #0x290]
100003250:     	adrp	x8, 0x1044ac000
100003254:     	ldr	x0, [x8, #0xc10]    ;; CLS:NSBundle
100003258:     	bl	0x1035dd7b4    ;; CALL:stub:_objc_opt_self
10000325c:     	bl	0x1035f4c00    ;; CALL:objc:mainBundle
100003260:     	mov	x29, x29
100003264:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
100003268:     	adrp	x8, 0x104651000
10000326c:     	str	x0, [x8, #0x298]
100003270:     	mov	x0, #0x0                ; =0
100003274:     	bl	0x1001072cc    ;; CALL:meta:Arc.BrowserApp
100003278:     	bl	0x1035de1a4    ;; CALL:stub:_swift_getObjCClassFromMetadata
10000327c:     	bl	0x1036074c0    ;; CALL:objc:sharedApplication
100003280:     	mov	x29, x29
100003284:     	bl	0x1035dd7fc    ;; CALL:stub:_objc_retainAutoreleasedReturnValue
100003288:     	adrp	x8, 0x104651000
10000328c:     	str	x0, [x8, #0x2a0]
100003290:     	bl	0x100b2ae4c    ;; CALL:fn:100b2ae4c
100003294:     	ldrb	w8, [x0]
100003298:     	cmp	w8, #0x1
10000329c:     	b.ne	0x1000032d0
1000032a0:     	adrp	x8, 0x10419f000
1000032a4:     	ldr	x8, [x8, #0x720]
1000032a8:     	adrp	x0, 0x100003000
1000032ac:     	add	x0, x0, #0x4b8
1000032b0:     	adrp	x2, 0x100003000
1000032b4:     	add	x2, x2, #0x580
1000032b8:     	add	x4, x8, #0x8
1000032bc:     	mov	x1, #0x0                ; =0
1000032c0:     	mov	x3, #0x0                ; =0
1000032c4:     	mov	x21, #0x0               ; =0
1000032c8:     	bl	0x10070587c    ;; CALL:fn:10070587c
1000032cc:     	b	0x1000032d4
1000032d0:     	bl	0x1000035a4    ;; CALL:fn:1000035a4
1000032d4:     	mov	w0, #0x0                ; =0
1000032d8:     	ldp	x29, x30, [sp, #0x30]
1000032dc:     	ldp	x20, x19, [sp, #0x20]
1000032e0:     	ldp	x22, x21, [sp, #0x10]
1000032e4:     	add	sp, sp, #0x40
1000032e8:     	ret
