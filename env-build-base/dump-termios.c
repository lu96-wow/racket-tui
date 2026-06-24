/*
 * dump-termios.c — 输出 termios 结构布局和常量值
 * 用于生成 base.rkt, 解决跨架构硬编码问题
 *
 * 用法: cc dump-termios.c -o dump-termios && ./dump-termios
 */

#include <stdio.h>
#include <termios.h>
#include <stddef.h>

int main(void) {
    struct termios t;

    /* 结构体大小 */
    printf("TERMIOS-SIZE %zu\n", sizeof(struct termios));

    /* 字段偏移 */
    printf("IFLAG-OFFSET %zu\n", offsetof(struct termios, c_iflag));
    printf("OFLAG-OFFSET %zu\n", offsetof(struct termios, c_oflag));
    printf("LFLAG-OFFSET %zu\n", offsetof(struct termios, c_lflag));

    /* c_cc 数组起始偏移和 VMIN/VTIME 索引 */
    printf("CC-OFFSET %zu\n", offsetof(struct termios, c_cc));
    printf("VMIN %d\n", VMIN);
    printf("VTIME %d\n", VTIME);

    /* 终端标志常量 */
    printf("TCSAFLUSH %d\n", TCSAFLUSH);
    printf("ICANON %d\n", ICANON);
    printf("ECHO %d\n", ECHO);
    printf("ISIG %d\n", ISIG);
#ifdef IEXTEN
    printf("IEXTEN %d\n", IEXTEN);
#else
    printf("IEXTEN 0\n");
#endif
    printf("IXON %d\n", IXON);
    printf("OPOST %d\n", OPOST);
    printf("ICRNL %d\n", ICRNL);
    printf("INLCR %d\n", INLCR);
    printf("IGNCR %d\n", IGNCR);
    printf("OCRNL %d\n", OCRNL);
    printf("ONLCR %d\n", ONLCR);

    return 0;
}
