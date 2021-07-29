//
//  IAMedia.h
//  YLCPlus
//
//  Created by yangyilin on 2021/7/1.
//
extern "C" {
#include <libavformat/avformat.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>
#include <libavutil/imgutils.h>
#include <libavutil/mathematics.h>
}
#include <stdio.h>


class IAMedia {
    AVFormatContext *_fmt_ctx, *_ofmt_ctx;
    AVStream *_video_stream , *_audio_stream;
    AVFrame *_frame;
    AVPacket _pkt;
    int _video_stream_idx, _audio_stream_idx;
    AVCodecContext *_video_dec_ctx, *_audio_dec_ctx;
    SwrContext *_resample_context;
    struct SwsContext *_sws_ctx;
    struct YLFiFO *_video_fifo, *_audio_fifo;
    FILE *_ff;
    long long _pts_base;
    bool recodeFlag, downloadFlag;
    long long _pre_v_pts, _pre_a_pts;
    int open_codec_context(int *stream_idx, AVCodecContext **dec_ctx, AVFormatContext *fmt_ctx, FFAVMediaType type);
    int decode_packet(AVCodecContext *dec, const AVPacket *pkt);
    int output_video_frame(AVFrame *frame);
    int output_audio_frame(AVFrame *frame);
    int init_resampler(SwrContext **resample_context, enum AVSampleFormat format);
    int init_converted_samples(uint8_t ***converted_input_samples, int **line_size, int channels, enum AVSampleFormat sample_fmt, int frame_size);
    int convert_samples(const uint8_t **input_data, uint8_t **converted_data, const int frame_size);
    int init_sws(struct SwsContext **sws, enum AVPixelFormat format);
    int init_converted_image(uint8_t ***converted_input_samples, int **line_size, int width, int height, enum AVPixelFormat format);
    int convert_image(const uint8_t **input_data, int *linesize1, uint8_t **converted_data, int *linesize2, int width, int height);
    int save_recode_pkg(AVPacket *pkg, AVStream *stream);
    int recode_newStream(AVStream *stream);
    int save_download_st(AVPacket *pkg, AVStream *stream);
    int creat_media_file(const char *filename);
public:
    ~IAMedia();
    int play(const char* url);
    int getSampleRate();
    int getSampleChanels();
    void (*renderData)(uint8_t *data, int size, int num);
    void (*renderYUV)(uint8_t *Y, uint8_t *U, uint8_t *V, int linesize, int width, int height);
    void (*renderRGB)(uint8_t *rgb, int linesize, int width, int height);
    int recode_media(const char *filename);
    int stop_recode_media();
    int download_Media(const char *filename);
    int stop_download_Media(const char *filename, bool iscontinue);
    int refleshFrame();
};
