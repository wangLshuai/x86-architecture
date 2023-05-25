
core_code_seg_sel   equ 0x38
core_data_seg_sel   equ 0x30
sys_routine_seg_sel equ 0x28
core_stack_seg_sel  equ 0x20
mem_0_4_gb_seg_sel  equ 0x18
video_ram_seg_sel   equ 0x10



core_length dd core_end  ;0x00

sys_routine_seg dd section.sys_routine.start ;0x04
core_data_seg dd section.core_data.start        ;0x08
core_code_seg dd section.core_code.start  ;汇编地址 ,0x0c
core_entry  dd start        ;段内偏移,0x10
            dw core_code_seg_sel  ;段选择子 ,0x38

[bits 32]
SECTION sys_routine vstart=0
put_string:         ;输入ds:ebx 字符串
    push ecx
.getc:
    mov cl,[ebx]
    or cl,cl
    jz .exit
    call put_char ;cl 不为0
    inc ebx
    jmp .getc
.exit:
    pop ecx
    retf

put_char:          ;输入cl为字符
    pushad          ;压栈 eax ecx edx ebx esp ebp esi edi, popad 按顺序出栈

    ;当前光标位置
    mov dx,0x3d4
    mov al,0x0e
    out dx,al
    inc dx
    in al,dx
    mov ah,al  ;保存光标高位

    dec dx
    mov al,0x0f
    out dx,al
    inc dx
    in al,dx
    mov bx,ax

    cmp cl,0x0d ;?回车符
    jnz .put_0a
    mov ax,bx
    mov bl,80
    div bl  ;ax = ax/80
    mul bl  ;ax=ax*80,当前行首位置
    mov bx,ax
    jmp .set_cursor

.put_0a:
    cmp cl,0x0a     ;换行符
    jnz .put_other
    add bx,80
    jmp .roll_screen

.put_other:          ;可打印字符
    push es
    mov eax,video_ram_seg_sel
    mov es,ax
    shl bx,1
    mov [es:bx],cl
    pop es

    shr bx,1
    inc bx

.roll_screen:
    cmp bx,2000
    jl .set_cursor

    push ds
    push es
    push ebx
    mov eax,video_ram_seg_sel
    mov ds,eax
    mov es,eax
    cld
    mov esi,0xa0
    mov edi,0x00
    mov ecx,1920
    rep movsw
    mov bx,3840
    mov ecx,80
.cls:
    mov word[es:bx],0x0720
    add bx,2
    loop .cls

    pop ebx
    pop es
    pop ds
    sub bx,80

.set_cursor:
    mov dx,0x3d4
    mov al,0x0e
    out dx,al
    inc dx
    mov al,bh
    out dx,al
    dec dx
    mov al,0x0f
    out dx,al
    inc dx
    mov al,bl
    out dx,al

    popad
    ret
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
    retf

allocate_memory: ;分配内存，输入ecx分配的字节，输出ecx 起始线性地址
    push ds
    push eax
    push ebx

    mov eax,core_data_seg_sel
    mov ds,eax

    mov eax,[ram_alloc]
    add eax,ecx

    mov ecx,[ram_alloc]

    ;4字节对齐下一次分配的起始地址
    mov ebx,eax
    add ebx,0xfffffffc
    add ebx,4
    test eax,0x00000003
    cmovnz eax,ebx
    mov [ram_alloc],eax

    pop ebx
    pop eax
    pop ds

    retf

set_up_gdt_descriptor: ;输入edx:eax 描述符，返回cx 描述符选择子

    push eax
    push ebx
    push edx

    push ds
    push es

    mov ebx,core_data_seg_sel
    mov ds,bx
    sgdt [pgdt]

    mov ebx,mem_0_4_gb_seg_sel
    mov es,ebx

    movzx ebx,word [pgdt] ;gdt 界限
    inc ebx
    add ebx,[pgdt+2]

    mov [es:ebx],eax
    mov [es:ebx+4],edx

    add word [pgdt],8

    lgdt [pgdt]

    mov ax,[pgdt]
    xor dx,dx
    mov bx,8
    div bx
    mov cx,ax
    shl cx,3   ;界限-7是最后一个描述符的起始偏移地址，也就是选择子

    pop es
    pop ds
    pop edx
    pop ebx
    pop eax
    retf


make_seg_descriptor:       ;输入EAX 线性地址，段的基地址，EBX 界限，ECX属性，返回EDX:EAX 段描述符
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
    retf

make_gate_descriptor:   ;输入eax函数偏移地址，bx选择子，cx属性;输出edx:eax
    push ecx
    push ebx

    push eax
    and eax,0x0000ffff
    shl ebx,16
    or eax,ebx

    pop edx
    and edx,0xffff0000
    or dx,cx

    pop ebx
    pop ecx
    retf

;------------------------------------------
initiate_task_switch:       ;主动发起任务切换，输入，输出无
    pushad
    push ds
    push es

    mov eax,core_data_seg_sel
    mov es,eax

    mov eax,mem_0_4_gb_seg_sel
    mov ds,eax

    mov eax,[es:tcb_chain]  ;tcb链表

    ;找到状态位忙的任务（当前任务）
.b0:
    cmp word [eax+0x04],0xffff
    cmove esi,eax      ;相等则mov
    jz .b1
    mov eax,[eax]   ;状态不为busy，下一个tcb
    jmp .b0

.b1:
    mov ebx,[eax]   ;下一个tcb
    or ebx,ebx      ;最后一个tcb的next是0
    jz .b2
    cmp word [ebx+0x04],0x0000
    cmove edi,ebx   ;相等则转移，找到就绪节点，保存到edi
    jz .b3
    mov eax,ebx
    jmp .b1

.b2 :
    mov ebx,[es:tcb_chain]
.b20:
    cmp word [ebx+0x04],0x0000
    cmove edi,ebx
    jz .b3
    mov ebx,[ebx]
    or ebx,ebx
    jz .return  ;到最后一个节点，找不到就绪，结束
    jmp .b20        

.b3:
    not word [esi+0x04]     ;当前任务tcb esi。设置任务状态为就绪
    not word [edi+0x04]     ;下一个任务tcb esi。设置为忙

    jmp far [edi+0x14]      ;下一个任务tss描述符，jmp 任务切换，当前b被清除,现场被保存到tss段中

.return
    pop es
    pop ds
    popad

    retf

;-----------------------------------------------
terminate_current_task:  ;终结当前任务，把任务tcb中的状态设置为0x3333,然后跳转到其他任务

    mov eax,core_data_seg_sel
    mov es,eax

    mov eax,mem_0_4_gb_seg_sel
    mov ds,eax

    mov eax,[es:tcb_chain]

    ;搜索状态位忙的tcb(当前任务)
.s0:
    cmp word [eax+0x04],0xffff
    jz .s1
    mov eax,[eax]
    jmp .s0

.s1
    mov word [eax+0x04],0x3333

    ;遍历，找到就绪任务
    mov ebx,[es:tcb_chain]

.s2:
    cmp word [ebx+0x04],0x0000
    jz .s3
    mov ebx,[ebx]
    jmp .s2


.s3:
    not word [ebx+0x04]
    jmp far [ebx+0x14]

;--------------------------------------------------
do_task_clean:  ;没有内存管理，无法回收资源，不做任何处理
    retf

SECTION core_data vstart=0

pgdt        dw 0
            dd 0
ram_alloc  dd 0x00100000   ;用户内存起始地址，初始化为1M，向上分配

;符号地址检索表
salt:
    salt_1      db '@PrintString'
                times 256-($-salt_1) db 0
                dd put_string
                dw sys_routine_seg_sel

    salt_2      db '@ReadDiskData'
                times 256-($-salt_2) db 0
                dd read_hard_disk_0
                dw sys_routine_seg_sel
    salt_3      db '@PrintDwordAsHexString'
                times 256-($-salt_3) db 0
                dd 0
                dw 0
    
    salt_4      db '@TerminateProgram'
                times 256-($-salt_4) db 0
                dd terminate_current_task
                dw sys_routine_seg_sel

    salt_5      db '@InitTaskSwitch'
                times 256-($-salt_5) db 0
                dd initiate_task_switch
                dw sys_routine_seg_sel
    salt_item_len equ $-salt_5
    salt_items  equ ($-salt)/salt_item_len

message_1  db  '  If you seen this message,that means we '
           db  'are now in protect mode,and the system '
           db  'core is loaded,and the video display '
           db  'routine works perfectly.',0x0d,0x0a,0
message_2  db  '    System wide CALL-GATE mounted.',0x0d,0x0a,0
message_5  db  ' Loading user program...',0

do_status        db  'Done.',0x0d,0x0a,0

message_6  db  0x0d,0x0a,0x0a,0x0a,0x0a
            db 'User program terminated,control returned.',0

core_buf times 2048 db 0

esp_pointer db 0

cpu_brnd0  db 0x0d,0x0a,' cpu id ',0
cpu_brand times 52 db 0
cpu_brnd1  db 0x0d,0x0a,0x0d,0x0a,0

tcb_chain      dd 0

core_msg1      db 0x0d,0x0a
                db '[CORE TASK]: I am running at CPL=0.Now,create '
                db 'user task and switch to it.',0x0d,0x0a,0

core_msg2       db 0x0d,0x0a
                db '[CORE TASK]: I am working!',0x0d,0x0a,0

core_msg3       db 0x0d,0x0a
                db '[CORE TASK]: No task to be switched,sleep!'
                db 0x0d,0x0a,0

SECTION core_code vstart=0

fill_descriptor_in_ldt: ;安装在ldt中一个描述符，edx:eax 是描述符，ebx=tcb基地址，输出cx描述符索引*8
    push eax
    push edx
    push edi
    push ds

    mov ecx,mem_0_4_gb_seg_sel
    mov ds,ecx

    mov edi,[ebx+0x0c] ;获得ldt 基址

    xor ecx,ecx
    mov cx,[ebx+0x0a]  ;界限
    inc cx             ;下一个描述符起始地址

    mov [edi+ecx],eax
    mov [edi+ecx+4],edx

    add cx,7
    mov [ebx+0x0a],cx

    and cx,0xfff8
    or cx,0x04          ;ldt

    pop ds
    pop edi
    pop edx
    pop eax
    ret


load_relocate_program:      ;push 起始逻辑扇区号，push tcb 
    pushad

    push ds
    push es

    mov ebp,esp

    mov ecx,mem_0_4_gb_seg_sel
    mov es,ecx

    mov esi,[ebp+11*4]  ;取出push的 tcb 地址，near call ,eip 4个字节，pushad 8*4个字节 push ds 4个字节 push es4个字节

    ;创建20个LDT
    mov ecx,160
    call sys_routine_seg_sel:allocate_memory
    mov [es:esi+0x0c],ecx   ;记录任务的ldt到tcb
    mov [es:esi+0x0a],word 0xffff ;8K个描述符？


    mov eax,core_data_seg_sel
    mov ds,eax

    mov eax,[ebp+12*4]  ;取出push的扇区号
    mov ebx,core_buf
    call sys_routine_seg_sel:read_hard_disk_0

    ;判断程序大小
    mov eax,[core_buf]
    mov ebx,eax
    and ebx,0xfffffe00
    add ebx,512       ;eax/512*512+512
    test eax,0x000001ff
    cmovnz eax,ebx     ;eax最后9位，不全为零，不是512的整数倍，向上取整数倍

    mov ecx,eax
    call sys_routine_seg_sel:allocate_memory
    mov [es:esi+0x06],ecx

    mov ebx,ecx
    xor edx,edx
    mov ecx,512
    div ecx
    mov ecx,eax

    mov eax,mem_0_4_gb_seg_sel
    mov ds,eax

    mov eax,[ebp+12*4]
.b1:
    call sys_routine_seg_sel:read_hard_disk_0
    inc eax
    loop .b1

    mov edi,[es:esi+0x06]
    mov eax,edi
    mov ebx,[edi+0x04]  ;app head len
    dec ebx             ;界限
    mov ecx,0x0040f200  ;1字节粒度，32位尺度，p存在，3特权，数据或代码段，读写数据段，向上扩展
    call sys_routine_seg_sel:make_seg_descriptor

    ;安装头部描述符到ldt中
    mov ebx,esi
    call fill_descriptor_in_ldt ;安装edx:eax 到esi->ldt
    or cx,0x03                 ;ldt,rpl特权为3
    mov [es:esi+0x44],cx
    mov [edi+0x04],cx

    ;程序代码段描述符
    mov eax,edi
    add eax,[edi+0x14]  ;代码段汇编地址加上 二进制加载首地址
    mov ebx,[edi+0x18]
    dec ebx
    mov ecx,0x0040f800 ;只执行代码段
    call sys_routine_seg_sel:make_seg_descriptor
    mov ebx,esi
    call fill_descriptor_in_ldt
    or cx,0x03
    mov [edi+0x14],cx


    ;程序数据段;
    mov eax,edi
    add eax,[edi+0x1c]
    mov ebx,[edi+0x20]
    dec ebx
    mov ecx,0x0040f200
    call sys_routine_seg_sel:make_seg_descriptor
    mov ebx,esi
    call fill_descriptor_in_ldt
    or cx,0x03
    mov [edi+0x1c],cx

    ;程序堆栈段
    mov ecx,[edi+0x0c]
    mov ebx,0x00100000
    sub ebx,ecx
    mov eax,4096
    mul dword [edi+0x0c]
    mov ecx,eax
    call sys_routine_seg_sel:allocate_memory
    add eax,ecx ;向下扩展的粒度为4kb的段,有n个4k大小，基址+(2^20-x)*4k 为下限ecx,或者基址+2^32 = ecx + n*4k，所以基址=ecx+n*4k
    mov ecx,0x00c0f600
    call sys_routine_seg_sel:make_seg_descriptor
    mov ebx,esi
    call fill_descriptor_in_ldt
    or cx,0x03
    mov [edi+0x08],cx

    ;重定位salt
    mov eax,mem_0_4_gb_seg_sel
    mov es,eax      ;0-4g数据段
    mov eax,core_data_seg_sel
    mov ds,eax      

    cld

    mov ecx,[es:edi+0x24]   ;salt 数目
    add edi,0x28        ;salt 起始偏移

.b2:
    push ecx
    push edi

    mov ecx,salt_items
    mov esi,salt

.b3:            ;循环比较core_data中的所有salt item
    push edi
    push esi
    push ecx

    mov ecx,64   ;最多比较64次
    repe cmpsd  ;ds:esi es:edi 每次比较双字，相等则继续比较下一个双字
    jnz .b4
    mov eax,[esi] ;匹配,取出core_data salt_item后的段内偏移地址
    mov [es:edi-256],eax
    mov ax,[esi+4] ;选择子
    or ax,0x03
    mov [es:edi-252],ax

.b4:

    pop ecx
    pop esi
    add esi,salt_item_len
    pop edi
    loop .b3
    ;遍历core_data中的所有salt item循环 结束

    pop edi
    add edi,256
    pop ecx
    loop .b2  ;app 中的下一个item

    mov esi,[ebp+11*4]  ;tcb基地址

    ;创建0特权堆栈
    mov ecx,4096
    mov eax,ecx
    mov [es:esi+0x1a],ecx  ;tcb,0特权 栈长度
    shr dword [es:esi+0x1a],12    ;0特权级 栈长度，4k单位
    call sys_routine_seg_sel:allocate_memory
    add eax,ecx      ;向下扩展的栈，上届为其基址
    mov [es:esi+0x1e],eax
    mov ebx,0xfffe  ;1个4k 段描述符的界限
    mov ecx,0x00c09600 ;4k粒度，32位尺度，读写，向下扩展段
    call sys_routine_seg_sel:make_seg_descriptor
    mov ebx,esi
    call fill_descriptor_in_ldt
    mov [es:esi+0x22],cx        ;堆栈选择子保存到tcb
    mov dword [es:esi+0x24],0   ;esp初始值

    ;创建1特权堆栈
    mov ecx,4096
    mov eax,ecx
    mov [es:esi+0x28],ecx
    shr dword [es:esi+0x28],12
    call sys_routine_seg_sel:allocate_memory
    add eax,ecx
    mov [es:esi+0x2c],eax
    mov ebx,0xfffe
    mov ecx,0x00c0b600  ;4k粒度，32位尺度，1特权级别，读写，详细扩展
    call sys_routine_seg_sel:make_seg_descriptor
    mov ebx,esi
    call fill_descriptor_in_ldt
    or cx,0x01
    mov [es:esi+0x30],cx
    mov dword [es:esi+0x32],0

    ;创建2特权堆栈
    mov ecx,4096
    mov eax,ecx
    mov [es:esi+0x36],ecx
    shr dword [es:esi+0x36],12
    call sys_routine_seg_sel:allocate_memory
    add eax,ecx
    mov [es:esi+0x3a],ecx
    mov ebx,0xffffe
    mov ecx,0x00c0d600
    call sys_routine_seg_sel:make_seg_descriptor
    mov ebx,esi
    call fill_descriptor_in_ldt
    or cx,0x02
    mov [es:esi+0x3e],cx
    mov dword [es:esi+0x40],0

    ;在gdt中登记ldt描述符
    mov eax,[es:esi+0x0c]       ;LDT的起始线性地址
    movzx ebx,word [es:esi+0x0a];LDT段界限
    mov ecx,0x00408200  ;1字节粒度，32位尺度，0特权级别，系统段，ldt
    call sys_routine_seg_sel:make_seg_descriptor
    call sys_routine_seg_sel:set_up_gdt_descriptor
    mov [es:esi+0x10],cx          ;

    ;创建用户程序tss
    mov ecx,104             ;tss大小
    mov [es:esi+0x12],cx
    dec word [es:esi+0x12]  ;tss界限
    call sys_routine_seg_sel:allocate_memory
    mov [es:esi+0x14],ecx   ;登记tss基地址到tcb

    ;登记基本的tss表格内容
    mov word [es:ecx],0

    mov edx,[es:esi+0x24]
    mov [es:ecx+4],edx

    mov dx,[es:esi+0x22]
    mov [es:ecx+8],dx

    mov edx,[es:esi+0x32]
    mov [es:ecx+12],edx

    mov edx,[es:esi+0x30]
    mov [es:ecx+16],edx

    mov edx,[es:esi+0x40]
    mov [es:ecx+20],edx

    mov edx,[es:esi+0x3e]
    mov [es:ecx+24],dx

    mov edx,[es:esi+0x10]
    mov [es:ecx+96],edx

    mov dx,[es:esi+0x12]
    mov [es:ecx+102],dx

    mov word [es:ecx+100],0
    mov dword [es:ecx+28],0 ;cr3,页式内存管理不开启
    ;访问用户程序头部，获取数据填充tss，cs eip ss ds
    mov ebx,[ebp+11*4]      ;tcb地址
    mov edi,[es:ebx+0x06]   ;用户程序加载的基地址,就是用户头基地址

    mov edx,[es:edi+0x10]   ;登记程序入口点
    mov dword [es:ecx+32],edx

    mov dx,[es:edi+0x14]    ;登记代码选择子cs
    mov [es:ecx+76],dx

    mov dx,[es:edi+0x08]    ;程序堆栈段选择子
    mov [es:ecx+80],dx

    mov dx,[es:edi+0x04]        ;程序数据段ds选择子,初始是app头部选择子
    mov [es:ecx+84],dx

    mov word [es:ecx+72],0      ;TSS ES
    mov word [es:ecx+88],0      ;FS=0

    mov word [es:ecx+92],0      ;GS=0

    pushfd
    pop dword [es:ecx+36]


    ;在GDT中登记TSS描述符
    mov eax,[es:esi+0x14]
    movzx ebx,word [es:esi+0x12]
    mov ecx,0x00008900  ;tss描述符 0特区
    call sys_routine_seg_sel:make_seg_descriptor
    call sys_routine_seg_sel:set_up_gdt_descriptor
    mov [es:esi+0x18],cx

    pop es
    pop ds

    popad
    ret 8
;----------------------------------------------------------------------
append_to_tcb_link:     ;在TCB链上追加任务控制块;输入ecx是tcb的线性基地址
    push eax
    push edx
    push ds
    push es

    mov eax,core_data_seg_sel
    mov ds,eax
    mov eax,mem_0_4_gb_seg_sel
    mov es,eax

    mov dword [es: ecx+0],0;下一个任务指针

    mov eax,[tcb_chain]     ;TCB表头指针
    or eax,eax
    jz .notcb
.searc:
    mov edx,eax
    mov eax,[es:edx+0x00] ;下一个tcb指针
    xor eax,eax           
    jnz .searc

    mov [es:edx+0x00],ecx   ;加到链表中
    jmp .retpc

.notcb
    mov [tcb_chain],ecx

.retpc
    pop es
    pop ds
    pop edx
    pop eax

    ret
;----------------------------------------------------------------------------
start:

    mov ax,core_data_seg_sel
    mov ds,ax

    mov ebx,message_1
    call sys_routine_seg_sel:put_string

    ;显示处理器品牌信息
    mov eax,0x80000002
    cpuid
    mov [cpu_brand + 0x00],eax
    mov [cpu_brand + 0x04],ebx
    mov [cpu_brand + 0x08],ecx
    mov [cpu_brand + 0x0c],edx

    mov eax,0x80000003
    cpuid
    mov [cpu_brand + 0x10],eax
    mov [cpu_brand + 0x14],ebx
    mov [cpu_brand + 0x18],ecx
    mov [cpu_brand + 0x1c],edx

    mov eax,0x80000004
    mov [cpu_brand + 0x20],eax
    mov [cpu_brand + 0x24],ebx
    mov [cpu_brand + 0x28],ecx
    mov [cpu_brand + 0x2c],edx

    mov ebx,cpu_brnd0
    call sys_routine_seg_sel:put_string
    mov ebx,cpu_brand
    call sys_routine_seg_sel:put_string
    mov ebx,cpu_brnd1
    call sys_routine_seg_sel:put_string

    ;安装系统服务调用门
    mov edi,salt
    mov ecx,salt_items

.b3:
    push ecx
    mov eax,[edi+256]
    mov bx, [edi+260]
    mov cx,1_11_0_1100_000_00000B    ;特权级别3，0个参数
    call sys_routine_seg_sel:make_gate_descriptor
    call sys_routine_seg_sel:set_up_gdt_descriptor
    mov [edi+260],cx
    add edi,salt_item_len
    pop ecx
    loop .b3

    ;调用门测试
    mov ebx,message_2
    call far [salt_1+256]
    mov ebx,message_5
    call sys_routine_seg_sel:put_string

    ;为内核任务创建任务控制块tcb
    mov ecx,0x46
    call sys_routine_seg_sel:allocate_memory
    call append_to_tcb_link
    mov esi,ecx

    ;为内核任务tss分配空间
    mov ecx,104
    call sys_routine_seg_sel:allocate_memory
    mov [es:esi+0x14],ecx   ;在tcb中保存tss基址

    ;设置tss
    mov word [es:ecx+96],0  ;ldt
    mov word [es:ecx+102],103   ;103    ;io位图基址。<=tss的界限符，没有io位图
    mov word [es:ecx],0         ;上一个任务tcb
    mov word [es:ecx+28],0      ;cr3寄存器，PDBR，不是用页式内存管理
    mov word [es:ecx+100],0     ;T=0,切换任务时触发异常，用于调试，不开启

    ;创建tss描述符，安装到gdt中
    mov eax,ecx     ;TSS 基址
    mov ebx,103     ;104-1,TSS界限
    mov ecx,0x00008900  ;属性，操作尺度16位？？？，字节粒度，p=1,0特权，系统段，tss描述符
    call sys_routine_seg_sel:make_seg_descriptor
    call sys_routine_seg_sel:set_up_gdt_descriptor
    mov word [es:esi+0x18],cx   ;保存tss选择子在tcb中
    mov word [es:esi+0x04],0xffff;在tcb中记录任务的状态为忙，0xffff忙，0x0000就绪，0x3333结束

    ;任务寄存器，load内核任务tss，内核任务就是当前任务，
    ;为当前任务“程序管理器”后补手续
    ltr cx  ;  gdt中的tss描述符属性b变为1，type由9变为b

    ;现在可以认为“程序管理器中任务正在进行”
    mov ebx,core_msg1
    call sys_routine_seg_sel:put_string


    ;创建用户任务控制块tcb
    mov ecx,0x46
    call sys_routine_seg_sel:allocate_memory
    mov word [es:ecx+0x04],0    ;就绪任务
    call append_to_tcb_link

    push dword 50
    push ecx

    call load_relocate_program


    ;可以创建更多的任务


.do_switch:
    ;主动切换到其他任务
    call sys_routine_seg_sel:initiate_task_switch

    mov ebx,core_msg2
    call sys_routine_seg_sel:put_string

    ;任务又切换回“任务管理器”
    ;清理结束状态的任务资源tcb tss 描述符
    call sys_routine_seg_sel:do_task_clean

    ;继续遍历tcb链表
    mov eax,[tcb_chain]
.find_ready:
    cmp word [es:eax+0x04],0x0000       ;任务处于就绪状态，可以被调度
    jz .do_switch
    mov eax,[es:eax]    ;下一个tcb
    or eax,eax
    jnz .find_ready

    ;遍历tcb链，没有就绪任务
    mov ebx,core_msg3
    call sys_routine_seg_sel:put_string

    hlt


SECTION core_trail
core_end: