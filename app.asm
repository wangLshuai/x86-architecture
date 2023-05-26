SECTION header vstart=0
    program_length  dd program_end ;0x00
    head_len        dd header_end     ;0x04

    stack_seg   dd 0                ;0x08
    stack_len   dd 1                ;0x0c

    prgentry    dd start            ;程序入口0x10
    code_seg    dd section.code.start   ;代码段汇编地址 0x14
    code_len    dd code_end         ;代码段长度,0x18

    data_seg    dd section.data.start;数据段汇编位置，0x1c
    data_len    dd data_end           ;0x20

;---------------------------------------------------------------------
    ;导入符号表，需要重定位
    salt_items dd (header_end-salt)/256 ;0x24
    salt:
    PrintString db '@PrintString'
        times 256-($-PrintString) db 0

    TerminateProgram db '@TerminateProgram'
        times 256-($-TerminateProgram) db 0

    ReadDiskData db '@ReadDiskData'
        times 256-($-ReadDiskData) db 0

    InitTaskSwitch db '@InitTaskSwitch'
                    times 256-($-InitTaskSwitch) db 0

header_end:

SECTION data vstart=0
    buffer times 1024 db 0 ;缓冲区
    message_1           db 0x0d,0x0a,0x0d,0x0a
                        db '[User TASK]: Hi! nice to meeet you,'
                        db 'I am run at CPL='
                    cpl db 0
                        db 0x0d,0x0a,0
    message_2           db '[USER TASK]: I needs to have a rest....',0x0d,0x0a,0

    message_3           db '[User TASK]: BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB,' ,0x0d,0x0a,0

data_end:

[bits 32]

SECTION code vstart=0
start:
    mov eax,ds
    mov fs,eax

    mov eax,[data_seg]
    mov ds,eax

    mov ax,cs
    and al,0x03     ;拿到rpl特权
    or al,0x30
    mov [cpl],al

    mov ebx,message_1
    call far [fs:PrintString]

    mov ebx,message_2
    call far [fs:PrintString]

.loop:
    mov ebx,message_3
    call far [fs:PrintString]
    jmp .loop

    call far [fs:TerminateProgram]
code_end:

SECTION program_trail 
program_end: