==== function 0x102e5122c (size 0x184)
102e5122c:     	orr	x29, x29, #0x1000000000000000
102e51230:     	sub	sp, sp, #0x60
102e51234:     	str	x27, [sp, #0x10]
102e51238:     	stp	x26, x25, [sp, #0x18]
102e5123c:     	stp	x24, x23, [sp, #0x28]
102e51240:     	stp	x21, x19, [sp, #0x38]
102e51244:     	stp	x29, x30, [sp, #0x50]
102e51248:     	str	x22, [sp, #0x48]
102e5124c:     	add	x29, sp, #0x50
102e51250:     	ldp	x25, x19, [x22, #0xb0]
102e51254:     	ldp	x8, x23, [x22, #0xa0]
102e51258:     	ldr	q0, [x8, #0x50]
102e5125c:     	str	q0, [x22, #0x10]
102e51260:     	ldp	q0, q1, [x8, #0x80]
102e51264:     	ldp	q3, q2, [x8, #0x60]
102e51268:     	stp	q0, q1, [x22, #0x40]
102e5126c:     	stp	q3, q2, [x22, #0x20]
102e51270:     	adrp	x0, 0x10463d000
102e51274:     	add	x0, x0, #0x1d0
102e51278:     	adrp	x1, 0x103845000
102e5127c:     	add	x1, x1, #0xfa0
102e51280:     	bl	0x100005134    ;; CALL:fn:100005134
102e51284:     	add	x8, x22, #0x60
102e51288:     	add	x20, x22, #0x10
102e5128c:     	bl	0x1006f2ba0    ;; CALL:fn:1006f2ba0
102e51290:     	ldr	x0, [x22, #0x68]
102e51294:     	bl	0x1035de3a8    ;; CALL:stub:_swift_release
102e51298:     	ldp	x26, x21, [x22, #0x70]
102e5129c:     	str	x21, [x22, #0xc0]
102e512a0:     	ldr	x0, [x22, #0x88]
102e512a4:     	bl	0x1035de3a8    ;; CALL:stub:_swift_release
102e512a8:     	ldr	x0, [x22, #0x98]
102e512ac:     	bl	0x1035de3a8    ;; CALL:stub:_swift_release
102e512b0:     	adrp	x0, 0x10463b000
102e512b4:     	add	x0, x0, #0xaf0
102e512b8:     	adrp	x1, 0x103841000
102e512bc:     	add	x1, x1, #0xb90
102e512c0:     	bl	0x100005134    ;; CALL:fn:100005134
102e512c4:     	mov	w1, #0x80               ; =128
102e512c8:     	mov	w2, #0x7                ; =7
102e512cc:     	bl	0x1035ddeb0    ;; CALL:stub:_swift_allocObject
102e512d0:     	mov	x24, x0
102e512d4:     	str	x0, [x22, #0xc8]
102e512d8:     	adrp	x8, 0x10365b000
102e512dc:     	ldr	q0, [x8, #0x720]    ;; Q:3e-323,6e-323 @0x10365b720
102e512e0:     	str	q0, [x0, #0x10]
102e512e4:     	adrp	x8, 0x103974000
102e512e8:     	add	x8, x8, #0x1c0    ;; CSTR:-customApplicationDataBaseURLPath
102e512ec:     	sub	x8, x8, #0x20
102e512f0:     	orr	x8, x8, #0x8000000000000000
102e512f4:     	mov	x27, #0x14              ; =20
102e512f8:     	movk	x27, #0xd000, lsl #48
102e512fc:     	add	x9, x27, #0xd
102e51300:     	stp	x9, x8, [x0, #0x20]
102e51304:     	mov	x20, x23
102e51308:     	bl	0x1035d29d8    ;; CALL:stub:_$s10Foundation3URLV4pathSSvg
102e5130c:     	stp	x0, x1, [x24, #0x30]
102e51310:     	adrp	x8, 0x103a35000
102e51314:     	add	x8, x8, #0xdc0    ;; CSTR:-shouldSkipUnboxingVideo
102e51318:     	sub	x8, x8, #0x20
102e5131c:     	orr	x8, x8, #0x8000000000000000
102e51320:     	add	x9, x27, #0x4
102e51324:     	stp	x9, x8, [x24, #0x40]
102e51328:     	adrp	x8, 0x103a35000
102e5132c:     	add	x8, x8, #0xde0    ;; CSTR:-cloudKitSyncEnabled
102e51330:     	stp	x25, x19, [x24, #0x50]
102e51334:     	sub	x8, x8, #0x20
102e51338:     	orr	x8, x8, #0x8000000000000000
102e5133c:     	stp	x27, x8, [x24, #0x60]
102e51340:     	mov	x8, #0x6166             ; =24934
102e51344:     	movk	x8, #0x736c, lsl #16
102e51348:     	movk	x8, #0x65, lsl #32
102e5134c:     	mov	x9, #-0x1b00000000000000 ; =-1945555039024054272    ;; STR:false
102e51350:     	stp	x8, x9, [x24, #0x70]
102e51354:     	ldp	w8, w20, [x26]
102e51358:     	sxtw	x8, w8
102e5135c:     	add	x0, x8, x26
102e51360:     	str	x0, [sp, #0x8]
102e51364:     	mov	x0, x19
102e51368:     	bl	0x1035ddf58    ;; CALL:stub:_swift_bridgeObjectRetain
102e5136c:     	mov	x0, x20
102e51370:     	bl	0x1035de474    ;; CALL:stub:_swift_task_alloc
102e51374:     	str	x0, [x22, #0xd0]
102e51378:     	adrp	x8, 0x102e51000
102e5137c:     	add	x8, x8, #0x3b0
102e51380:     	stp	x22, x8, [x0]
102e51384:     	mov	x22, x0
102e51388:     	mov	x0, x24
102e5138c:     	mov	x20, x21
102e51390:     	ldp	x1, x27, [sp, #0x8]
102e51394:     	ldp	x29, x30, [sp, #0x50]
102e51398:     	ldp	x21, x19, [sp, #0x38]
102e5139c:     	ldp	x24, x23, [sp, #0x28]
102e513a0:     	ldp	x26, x25, [sp, #0x18]
102e513a4:     	and	x29, x29, #0xefffffffffffffff
102e513a8:     	add	sp, sp, #0x60
102e513ac:     	br	x1
