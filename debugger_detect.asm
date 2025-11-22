; debugger_detect.asm - check /proc/self/status for "TracerPid"
; NASM, x86_64 Linux

section .data
path db '/proc/self/status',0
needle db 'TracerPid:',0
out_ok db 'No debugger detected (TracerPid: 0)',10,0
out_dbg db 'Debugger detected (TracerPid != 0)',10,0

section .bss
buf resb 4096

section .text
global _start

_start:
    ; open("/proc/self/status", O_RDONLY)
    mov rax, 2              ; sys_open
    lea rdi, [rel path]
    xor rsi, rsi            ; flags = 0
    syscall
    cmp rax, 0
    jl cannot_open
    mov rdi, rax            ; fd

    ; read(fd, buf, 4096)
    mov rax, 0              ; sys_read
    mov rsi, buf
    mov rdx, 4096
    syscall
    mov rcx, rax            ; bytes read

    ; close(fd)
    mov rax, 3              ; sys_close
    syscall

    ; search for "TracerPid:"
    lea rsi, [rel buf]
    mov rdi, needle
    mov r8, rcx             ; length read
    call find_substr
    ; rax = index (>=0) or -1

    cmp rax, -1
    je cannot_find

    ; rax is offset of 'T' relative to buf; check char after "TracerPid:\t"
    ; compute pointer to after "TracerPid:"
    mov rbx, rax
    add rbx, 10             ; length of "TracerPid:" is 10
    ; allow for tabs/spaces - search for digit after some whitespace
    mov rsi, buf
    add rsi, rbx            ; rsi -> candidate char
    ; skip whitespace
.skip_ws:
    mov al, byte [rsi]
    cmp al, 9   ; tab
    je .ws_next
    cmp al, 32  ; space
    je .ws_next
    jmp .check_digit
.ws_next:
    inc rsi
    jmp .skip_ws

.check_digit:
    mov al, byte [rsi]
    cmp al, '0'
    jl .dbg
    cmp al, '9'
    jg .dbg
    ; if digit is '0' - check if zero
    cmp al, '0'
    je .print_no_dbg
    jmp .print_dbg

.print_no_dbg:
    ; write out_ok
    lea rax, [rel out_ok]
    mov rdi, 1
    mov rsi, rax
    mov rdx, 33
    mov rax, 1
    syscall
    jmp exit

.print_dbg:
    lea rax, [rel out_dbg]
    mov rdi, 1
    mov rsi, rax
    mov rdx, 31
    mov rax, 1
    syscall
    jmp exit

.cannot_open:
    ; fallback message
    lea rax, [rel out_dbg]
    mov rdi, 1
    mov rsi, rax
    mov rdx, 31
    mov rax, 1
    syscall
    jmp exit

.cannot_find:
    ; if cannot find, print dbg message
    lea rax, [rel out_dbg]
    mov rdi, 1
    mov rsi, rax
    mov rdx, 31
    mov rax, 1
    syscall
    jmp exit

; simple substring search:
; rdi = needle (ptr), rsi = haystack (ptr), r8 = hay_len
; returns rax = index into haystack (0-based) or -1
find_substr:
    push rbp
    mov rbp, rsp
    ; compute lens
    ; len(needle)
    xor rcx, rcx
.find_len:
    cmp byte [rdi+rcx], 0
    je .len_done
    inc rcx
    jmp .find_len
.len_done:
    mov r9, rcx    ; needle length

    ; if needle length == 0 -> 0
    cmp r9, 0
    je .ret0

    xor r10, r10   ; idx = 0
.loop_hay:
    cmp r10, r8
    jae .not_found
    ; if remaining < needle length => not found
    mov r11, r8
    sub r11, r10
    cmp r11, r9
    jb .not_found

    ; compare haystack[r10 .. r10+r9-1] with needle
    mov rcx, 0
.cmp_loop:
    mov al, [rsi + r10 + rcx]
    cmp al, [rdi + rcx]
    jne .next_idx
    inc rcx
    cmp rcx, r9
    jne .cmp_loop
    ; matched
    mov rax, r10
    pop rbp
    ret
.next_idx:
    inc r10
    jmp .loop_hay

.not_found:
    mov rax, -1
    pop rbp
    ret

.ret0:
    mov rax, 0
    pop rbp
    ret

exit:
    mov rax, 60
    xor rdi, rdi
    syscall
