.PHONY:run
run: image
	./run.sh
.PHONY: debug
debug: image
	./run.sh debug &
	# refer https://astralvx.com/debugging-16-bit-in-qemu-with-gdb-on-windows/
	gdb -ex "target remote localhost:1234" -ex "b *0x7c00" -ex "c"

image: mbr.bin kernel.bin app.bin app1.bin
	# dd if=/dev/zero of=image.raw bs=1M count=1
	dd if=mbr.bin of=image.raw conv=notrunc
	dd if=kernel.bin of=image.raw bs=512 seek=1 conv=notrunc
	dd if=app.bin of=image.raw bs=512 seek=50 conv=notrunc
	dd if=app1.bin of=image.raw bs=512 seek=100 conv=notrunc
mbr.bin:gdt_mbr.asm
	nasm -f bin -l gdt_mbr.lst gdt_mbr.asm -o mbr.bin

kernel.bin:kernel.asm
	nasm -f bin -l kernel.lst kernel.asm -o kernel.bin

app.bin:app.asm
	nasm -f bin -l app.lst app.asm -o app.bin
app1.bin:app1.asm
	nasm -f bin -l app1.lst app1.asm -o app1.bin

.PHONY:clean
clean:
	rm -rf *.bin *.o *.lst