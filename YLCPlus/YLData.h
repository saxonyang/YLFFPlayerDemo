//
//  YLData.h
//  YLCPlus
//
//  Created by yangyilin on 2021/7/28.
//

#ifndef YLData_h
#define YLData_h

struct YLFiFO {
    struct YLFiFOData *last;
    struct YLFiFOData *fist;
    int size;
};

struct YLFiFOData {
    uint8_t *buf;
    int linesize;
    int width;
    int heigth;
    double pts;
    struct YLFiFOData *next;
    struct YLFiFOData *pre;
};

#endif /* YLData_h */
