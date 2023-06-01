core_base_address equ 0x00040000  ;内核加载地址,第252k
core_start_sector equ 0x00000001  ;内核在硬盘上第1扇区

;======================================================
SECTION mbr vstart=0x00007c00
mov ax,cs
mov ss,ax
mov sp,0x7c00

;gdt_base是相对段起始的汇编地址，mbr被加载到了0x7c00,所以即是内存地址
mov eax,[gdt_base]
xor edx,edx

mov ebx,16
div ebx

mov ds,ax

mov ebx,edx
mov dword [ebx],0x00   
mov dword [ebx+4],0x00 ;0段描述符为null

;1段描述符，保护模式下的代码描述符，特权级别0,基址0，界限0xfffff,4k粒度
mov dword [ebx+0x08],0x0000ffff
mov dword [ebx+0x0c],0x00cf9800

;2段描述符，保护模式下的数据段和堆栈描述符，特权级别0，基地址0，界限0xfffff,4k粒度
mov dword [ebx+0x10],0x0000ffff
mov dword [ebx+0x14],0x00cf9200

;3段描述符，保护模式下的代码描述符，特权级3，基址0，界限0xfffff，4k粒度
mov dword [ebx+0x18],0x0000ffff
mov dword [ebx+0x1c],0x00cff800

;4段描述符，保护模式下的数据段和堆栈段，特权为3，基地址0，界限0xfffff，4K粒度
mov dword [ebx+0x20],0x0000ffff
mov dword [ebx+0x24],0x00cff200


mov word [cs:gdt_size],39 ;gdtr 48位，高32位是gdt表起始地址，低16位是gdt边界。两个描述符，5*8-1
lgdt [cs:gdt_size]

; 打开20号地址线
in al,0x92
or al,0000_0010B
out 0x92,al

cli  ;保护模式下中断未建立，禁止中断

mov eax,cr0
or eax,0x01
mov cr0,eax  ;使能保护模式;此时代码还使用实模式cs生成的在告诉描述符缓冲里的段描述符

jmp dword 0x0008:flush
[bits 32]
flush:
    mov ax,0x10 ;使用2#段
    mov ss,ax
    mov ds,ax
    mov es,ax
    mov fs,ax
    mov gs,ax
    mov esp,0x7c00

    mov edi,core_base_address
    mov eax,core_start_sector
    mov ebx,edi
    call read_hard_disk_0

    mov eax,[edi]   ;core_length
    xor edx,edx
    mov ecx,512
    div ecx

    or edx,edx
    jnz @1     ;edx 1=0 ,有余数 ，跳转
    dec eax
@1:
    or eax,eax
    jz setup    ;eax 为0，不需要继续读

    ;读剩余扇区
    mov ecx,eax
    mov eax,core_start_sector
    inc eax
@2:
    call read_hard_disk_0
    inc eax
    loop @2

setup:
    ;建立页目录和页表，使用分页机制
    mov ebx,0x00020000  ;页目录pdt物理地址

    ;页目录的最后一项指向自己
    mov dword [ebx+4092],0x00020003

    mov edx,0x00021003  ;页表,一个页表可映射4M空间
    mov dword [ebx],edx

    ;高2G虚拟空间映射
    mov [ebx+0x800],edx

    ;初始化页表，线性映射
    mov ebx,0x00021000
    xor eax,eax
    xor esi,esi
.b1:
    mov edx,eax
    or edx,0x00000003
    mov [ebx+esi*4],edx
    add eax,0x1000  ;下一页
    inc esi
    cmp esi,256     ;只映射低1M
    jl .b1

    ;cr3设置页目录地址
    mov eax,0x00020000
    mov cr3,eax

    ;将gdt的线性地址同样改到高2G空间
    sgdt [gdt_size]
    add dword [gdt_base],0x80000000
    lgdt [gdt_size]

    mov eax,cr0
    or eax,0x80000000
    mov cr0,eax         ;开启页管理

    add esp,0x80000000  ;esp也在高端2G

    jmp [0x80040004]

read_hard_disk_0:  ;从主硬盘读取一个逻辑扇区 输入EAX:为硬盘逻辑扇区，DS:EBX内存缓冲区，返回：EBX=EBX+512
    push eax
    push ecx
    push edx

    push eax
    mov dx,0x1f2
    mov al,1
    out dx,al        ;操作一个扇区

    inc dx          ;0x1f3
    pop eax
    out dx,al       ;LBA 地址7-0,总共有28位逻辑扇区编号

    inc dx          ;0x1f4
    shr eax,8       
    out dx,al       ;LBA 8-15


    inc dx          ;0x1f5
    shr eax,8
    out dx,al       ;LBA 16-23

    inc dx          ;0x1f6
    shr eax,8
    or al,0xe0      ; LBA28模式，主盘。LBA 24-27位

    inc dx          ;0x1f7
    mov al,0x20
    out dx,al       ;读取命令

.waits:
    in al,dx
    and al,0x88
    cmp al,0x08
    jnz .waits       ;不相等则忙碌，等待数据准备好

    mov ecx,256
    mov dx,0x1f0    ;硬盘io输入端口号

.readw:
    in ax,dx
    mov [ebx],ax
    add ebx,2
    loop .readw

    pop edx
    pop ecx
    pop eax
    ret

make_gdt_descriptor:       ;输入EAX 线性地址，段的基地址，EBX 界限，ECX属性，返回EDX:EAX 段描述符
    mov edx,eax
    shl eax,16
    or ax,bx       ;eax是8字节段描述符的低4字节，高16位是段基地址的0-15位，低16位是界限符的0-15位

    ;配置段描述符的高4字节，存放在edx寄存器中
    and edx,0xffff0000
    rol edx,8   ;段基地址的24-31位在0-7,16-23在24-31位
    bswap edx   ;交换高和低地址数据24-31位在24-31位，16-23位在0-7位

    xor bx,bx   ;ebx 段界限，16-19位
    or edx,ebx

    or edx,ecx  ;属性，8-11，type;12-15 p dpl s;20-23,p d/b avl l
    ret





gdt_size: dw 0
gdt_base: dd 0x00008000

times 510-($-$$) db 0
db 0x55,0xaa