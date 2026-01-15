// ncurses-help.c
#include <curses.h>
#include <string.h>
#include <stdio.h>

// 返回 ALL_MOUSE_EVENTS 的值（供 Racket 启用鼠标）
mmask_t help_get_ALL_MOUSE_EVENTS(void) {
    return ALL_MOUSE_EVENTS;
}

// 获取并解析鼠标事件，返回格式化字符串
const char* help_get_mouse_event_string(void) {
    static char buf[128];
    MEVENT ev;

    if (getmouse(&ev) != OK) {
        strcpy(buf, "mouse-get-failed");
        return buf;
    }

    mmask_t bstate = ev.bstate;
    short id = ev.id;
    int x = ev.x;
    int y = ev.y;

    // 修饰键
    const char *mod = "";
    if (bstate & BUTTON_CTRL)  mod = "ctrl-";
    else if (bstate & BUTTON_SHIFT) mod = "shift-";
    else if (bstate & BUTTON_ALT)   mod = "alt-";
    // 注意：现实中可能有组合（如 ctrl+shift），但 ncurses 通常只设一个
    // 若需支持组合，需拼接字符串，但这里按原逻辑简化

    // 辅助宏：检查某按钮某事件
    #define CHECK_BTN(btn_num, btn_name_str) do { \
        mmask_t clicked     = NCURSES_MOUSE_MASK(btn_num, NCURSES_BUTTON_CLICKED); \
        mmask_t dclicked    = NCURSES_MOUSE_MASK(btn_num, NCURSES_DOUBLE_CLICKED); \
        mmask_t tclicked    = NCURSES_MOUSE_MASK(btn_num, NCURSES_TRIPLE_CLICKED); \
        mmask_t pressed     = NCURSES_MOUSE_MASK(btn_num, NCURSES_BUTTON_PRESSED); \
        mmask_t released    = NCURSES_MOUSE_MASK(btn_num, NCURSES_BUTTON_RELEASED); \
        \
        if (bstate & tclicked) { \
            snprintf(buf, sizeof(buf), "%smouse-%s-triple-click %d %d %d", mod, btn_name_str, (int)id, x, y); \
            return buf; \
        } else if (bstate & dclicked) { \
            snprintf(buf, sizeof(buf), "%smouse-%s-double-click %d %d %d", mod, btn_name_str, (int)id, x, y); \
            return buf; \
        } else if (bstate & clicked) { \
            snprintf(buf, sizeof(buf), "%smouse-%s-click %d %d %d", mod, btn_name_str, (int)id, x, y); \
            return buf; \
        } else if (bstate & pressed) { \
            snprintf(buf, sizeof(buf), "%smouse-%s-press %d %d %d", mod, btn_name_str, (int)id, x, y); \
            return buf; \
        } else if (bstate & released) { \
            snprintf(buf, sizeof(buf), "%smouse-%s-release %d %d %d", mod, btn_name_str, (int)id, x, y); \
            return buf; \
        } \
    } while(0)

    // 按钮 1～3：左、中、右
    if (bstate & (BUTTON1_PRESSED | BUTTON1_RELEASED | BUTTON1_CLICKED |
                  BUTTON1_DOUBLE_CLICKED | BUTTON1_TRIPLE_CLICKED)) {
        CHECK_BTN(1, "left");
    }
    if (bstate & (BUTTON2_PRESSED | BUTTON2_RELEASED | BUTTON2_CLICKED |
                  BUTTON2_DOUBLE_CLICKED | BUTTON2_TRIPLE_CLICKED)) {
        CHECK_BTN(2, "middle");
    }
    if (bstate & (BUTTON3_PRESSED | BUTTON3_RELEASED | BUTTON3_CLICKED |
                  BUTTON3_DOUBLE_CLICKED | BUTTON3_TRIPLE_CLICKED)) {
        CHECK_BTN(3, "right");
    }

    // 滚轮：button 4 (up), 5 (down)，只有 PRESSED
    if (bstate & BUTTON4_PRESSED) {
        snprintf(buf, sizeof(buf), "%smouse-wheel-up %d", mod, (int)id);
        return buf;
    }
    if (bstate & BUTTON5_PRESSED) {
        snprintf(buf, sizeof(buf), "%smouse-wheel-down %d", mod, (int)id);
        return buf;
    }

    // 未识别
    snprintf(buf, sizeof(buf), "mouse-unknown %lu %d %d %d",
             (unsigned long)bstate, (int)id, x, y);
    return buf;
}

int help_get_COLORS(void) {
    return COLORS;
}

int help_get_COLOR_PAIRS(void) {
    return COLOR_PAIRS;
}

chtype help_COLOR_PAIR(int n) {
    return COLOR_PAIR(n);
}