//
//  IAMedia.m
//  YLCPlus
//
//  Created by yangyilin on 2021/7/1.
//
#import <UIKit/UIKit.h>
#include <string>
#include <sys/stat.h>
using namespace std;
#include "IAMedia.h"
#include "YLData.h"

#define SWS_BILINEAR 2
#define PIXFORMAT AV_PIX_FMT_RGBA //AV_PIX_FMT_YUV420P
#define AVFORMAT AV_SAMPLE_FMT_FLTP




void init_fifo(struct YLFiFO **fifo) {
    *fifo = (struct YLFiFO *)malloc(sizeof(YLFiFO));
    (*fifo)->size = 0;
}

void free_fifo(struct YLFiFO **fifo) {
    struct YLFiFO *p = *fifo;
    struct YLFiFOData *cur = p->fist;
    while (cur != NULL) {
        struct YLFiFOData *q = cur->next;
        free(cur->buf);
        free(cur);
        cur = q;
    }
    free(p);
}

void push_fifo(struct YLFiFO **fifo, uint8_t *buf, int linesize, int width, int height, double pts) {
    struct YLFiFO *p = *fifo;
    struct YLFiFOData *a = (struct YLFiFOData *)malloc(sizeof(YLFiFOData));
    a->buf = (uint8_t *)calloc(linesize*height, sizeof(uint8_t));
    memcpy(a->buf, buf, linesize*height);
    a->pts = pts;
    a->linesize = linesize;
    a->width = width;
    a->heigth = height;
    a->next = NULL;
    if (p->size > 0) {
        p->last->next = a;
        a->pre = p->last;
        p->last = a;
    } else {
        p->fist = p->last = a;
        a->pre = NULL;
    }
    p->size += 1;
}

void pop_fifo(struct YLFiFO **fifo, struct YLFiFOData **e) {
    struct YLFiFO *p = *fifo;
    if (p->size == 0) {
        *e = NULL;
        return;
    }
    *e = p->fist;
    p->fist = p->fist->next;
    if (p->fist)
        p->fist->pre = NULL;
    p->size -= 1;
    if (p->size == 0) {
        p->last = NULL;
    }
}

int IAMedia::getSampleRate() {
    return  _video_dec_ctx->sample_rate;
}

int IAMedia::getSampleChanels() {
    return  _video_dec_ctx->channels;
}

IAMedia::~IAMedia(void) {
    if (_video_dec_ctx) {
        avcodec_free_context(&_video_dec_ctx);
    }
    if (_audio_dec_ctx) {
        avcodec_free_context(&_audio_dec_ctx);
    }
    if (_fmt_ctx) {
        avformat_close_input(&_fmt_ctx);
    }
    if (_frame) {
        av_frame_free(&_frame);
    }
    if (_resample_context) {
        swr_free(&_resample_context);
    }
    if (_sws_ctx) {
        sws_freeContext(_sws_ctx);
    }
    if (_video_fifo) {
        free_fifo(&_video_fifo);
    }
    if (_audio_fifo) {
        free_fifo(&_audio_fifo);
    }
}

int IAMedia::play(const char* url) {
    init_fifo(&_video_fifo);
    init_fifo(&_audio_fifo);
    AVDictionary *opts = NULL;
    av_dict_set(&opts, "rtsp_transport", "tcp", 0);
    if (avformat_open_input(&_fmt_ctx, url, NULL, &opts) < 0) {
        printf("open %s fail", url);
        return -1;
    }
    if (avformat_find_stream_info(_fmt_ctx, NULL) < 0) {
        printf("not find stream \n");
        return -1;
    }
    if (IAMedia::open_codec_context(&_video_stream_idx, &_video_dec_ctx, _fmt_ctx, AVMEDIA_TYPE_VIDEO) >= 0) {
        _video_stream = _fmt_ctx->streams[_video_stream_idx];
    }
    if (IAMedia::open_codec_context(&_audio_stream_idx, &_audio_dec_ctx, _fmt_ctx, AVMEDIA_TYPE_AUDIO) >= 0) {
        _audio_stream = _fmt_ctx->streams[_audio_stream_idx];
    }
     
    if (!_audio_stream && !_video_stream) {
        printf("Could not find audio or video stream in the input, aborting\n");
        return -1;
    }
    IAMedia::init_resampler(&_resample_context, AVFORMAT);
    IAMedia::init_sws(&_sws_ctx, PIXFORMAT);
    _frame = av_frame_alloc();
    if (!_frame) {
        printf("Could not allocate frame\n");
        return -1;
    }
    av_init_packet(&_pkt);
    _pkt.data = NULL;
    _pkt.size = 0;
    int ret = 0;
    char mflag = 0;
    bool pflag = false;
    while (av_read_frame(_fmt_ctx, &_pkt) >= 0) {
        bool flag = false;
        if (_pkt.stream_index == _video_stream_idx) {
            flag = true;
            mflag = 0;
            ret = IAMedia::decode_packet(_video_dec_ctx, &_pkt);
        } else if (_pkt.stream_index == _audio_stream_idx) {
            flag = true;
            mflag = 1;
            ret = IAMedia::decode_packet(_audio_dec_ctx, &_pkt);
        }
    
        if (recodeFlag && flag && _ofmt_ctx) {
            if (!pflag) {
                pflag = _pkt.flags == 1;
                printf("start recode mp4");
            }
            if (pflag) {
                IAMedia::save_recode_pkg(&_pkt, _pkt.stream_index == _video_stream_idx ? _video_stream : _audio_stream);
            }
        }
        if (downloadFlag && _ff && flag) {
            if (!pflag) {
                pflag = _pkt.flags == 1;
                printf("start recode mp4");
            }
            if (pflag) {
                IAMedia::save_download_st(&_pkt, _pkt.stream_index == _video_stream_idx ? _video_stream : _audio_stream);
            }
        }
        av_packet_unref(&_pkt);
        if (ret < 0) {
            break;
        }
    }
    if (_video_dec_ctx) {
        IAMedia::decode_packet(_video_dec_ctx, NULL);
    }
    if (_audio_dec_ctx) {
        IAMedia::decode_packet(_audio_dec_ctx, NULL);
    }
    return 1;
}

int IAMedia::open_codec_context(int *stream_idx, AVCodecContext **dec_ctx, AVFormatContext *fmt_ctx, FFAVMediaType type) {
    int ret, stream_index;
    AVStream *st;
    AVCodec *dec = NULL;
    ret = av_find_best_stream(fmt_ctx, type, -1, -1, NULL, 0);
    if (ret < 0) {
        printf("Could not find stream in input file");
        return ret;
    } else {
        stream_index = ret;
        st = fmt_ctx->streams[stream_index];
        dec = avcodec_find_decoder(st->codecpar->codec_id);
        if (!dec) {
            printf("Could not find codec");
            return -1;
        }
        *dec_ctx = avcodec_alloc_context3(dec);
        if (!*dec_ctx) {
            printf("Failed to allocate codec context");
            return -1;
        }
        if ((ret = avcodec_parameters_to_context(*dec_ctx, st->codecpar)) < 0) {
            printf("Failed to copy codec parameters to decoder context\n");
            return -1;
        }
        if ((ret = avcodec_open2(*dec_ctx, dec, NULL)) < 0) {
            printf("Failed to open codec");
            return -1;
        }
        *stream_idx = stream_index;
    }
    return  1;
}

int IAMedia::decode_packet(AVCodecContext *dec, const AVPacket *pkt) {
    int ret = 0;
    ret = avcodec_send_packet(dec, pkt);
    if (ret < 0) {
        fprintf(stderr, "Error submitting a packet for decoding (%s)\n", av_err2str(ret));
        return ret;
    }
    while (ret >= 0) {
        ret = avcodec_receive_frame(dec, _frame);
        if (ret < 0) {
            if (ret == AVERROR_EOF || ret == AVERROR(EAGAIN))
                return 0;
            fprintf(stderr, "Error during decoding (%s)\n", av_err2str(ret));
            return ret;
        }
        if (dec->codec->type == AVMEDIA_TYPE_VIDEO) {
            ret = IAMedia::output_video_frame(_frame);
        } else if (dec->codec->type == AVMEDIA_TYPE_AUDIO) {
            ret = IAMedia::output_audio_frame(_frame);
        }
        av_frame_unref(_frame);
        if (ret < 0)
            return ret;
    }
    return 0;
}

int IAMedia::output_audio_frame(AVFrame *frame) {
    uint8_t **data = NULL;
    int *linesize = NULL;
    if (IAMedia::init_converted_samples(&data, &linesize, _audio_dec_ctx->channels, AVFORMAT, frame->nb_samples) < 0) {
        printf("audio output buffer alloc fail");
        return -1;
    }
    if (IAMedia::convert_samples((const uint8_t **)frame->extended_data, data, frame->nb_samples) < 0) {
        printf("audio convert samples fail");
        return -1;
    }
    push_fifo(&_audio_fifo, data[0], linesize[0], frame->nb_samples, 1, frame->pts*av_q2d(_audio_stream->time_base));
    if (data) {
        av_freep(&data[0]);
        free(data);
        free(linesize);
    }
    return 0;
}

int IAMedia::output_video_frame(AVFrame *frame) {
    uint8_t **data = NULL;
    int *linesize = NULL;
    if (IAMedia::init_converted_image(&data, &linesize, frame->width, frame->height, PIXFORMAT) < 0) {
        printf("video output buffer alloc fail");
        return -1;
    }
    if (IAMedia::convert_image((const uint8_t **)frame->extended_data, frame->linesize, data, linesize, frame->width, frame->height) < 0) {
        printf("video convert samples fail");
        return -1;
    }
    push_fifo(&_video_fifo, data[0], linesize[0], frame->width, frame->height, frame->pts*av_q2d(_video_stream->time_base));
//    if (IAMedia::renderYUV) {
//        (*IAMedia::renderYUV)(data[0], data[1], data[2], linesize[0], frame->width, frame->height);
//    }
//    if (IAMedia::renderRGB) {
//        (*IAMedia::renderRGB)((uint8_t *)c, linesize[0], frame->width, frame->height);
//    }
    if (data) {
        av_freep(&data[0]);
        free(data);
        free(linesize);
    }
    return 0;
}
//
int IAMedia::init_resampler(SwrContext **resample_context, enum AVSampleFormat format) {
    int error;
    *resample_context = swr_alloc_set_opts(NULL,
                                          av_get_default_channel_layout(_audio_dec_ctx->channels),
                                           format,
                                           _audio_dec_ctx->sample_rate,
                                          av_get_default_channel_layout(_audio_dec_ctx->channels),
                                           _audio_dec_ctx->sample_fmt,
                                           _audio_dec_ctx->sample_rate,
                                          0, NULL);
    if (!*resample_context) {
        fprintf(stderr, "Could not allocate resample context\n");
        return AVERROR(ENOMEM);
    }
    if ((error = swr_init(*resample_context)) < 0) {
        fprintf(stderr, "Could not open resample context\n");
        swr_free(resample_context);
        return error;
    }
    return 0;
}

int IAMedia::init_converted_samples(uint8_t ***converted_input_samples, int **line_size, int channels, enum AVSampleFormat sample_fmt, int frame_size) {
    int error;
    if (!(*converted_input_samples = (uint8_t **)calloc(channels,
                                            sizeof(**converted_input_samples)))) {
        fprintf(stderr, "Could not allocate converted input sample pointers\n");
        return AVERROR(ENOMEM);
    }
    if (!(*line_size = (int *)calloc(channels,
                                            sizeof(int)))) {
        fprintf(stderr, "Could not allocate converted input sample pointers\n");
        return AVERROR(ENOMEM);
    }
    if ((error = av_samples_alloc(*converted_input_samples, *line_size,
                                  channels,
                                  frame_size,
                                  sample_fmt, 0)) < 0) {
        fprintf(stderr,
                "Could not allocate converted input samples (error '%s')\n",
                av_err2str(error));
        av_freep(&(*converted_input_samples)[0]);
        free(*converted_input_samples);
        return error;
    }
    return 0;
}

int IAMedia::convert_samples(const uint8_t **input_data,
                             uint8_t **converted_data, const int frame_size) {
    int error;
    if ((error = swr_convert(_resample_context,
                           converted_data, frame_size,
                           input_data    , frame_size)) < 0) {
      fprintf(stderr, "Could not convert input samples (error '%s')\n",
              av_err2str(error));
      return error;
    }
    return 0;
}

int IAMedia::init_sws(struct SwsContext **sws, enum AVPixelFormat format) {
    int w = _video_dec_ctx->width;
    int h = _video_dec_ctx->height;
    *sws = sws_getContext(w, h, _video_dec_ctx->pix_fmt,
                                 w, h, format,
                                 SWS_BILINEAR, NULL, NULL, NULL);
    if (!*sws) {
        printf("Impossible to create scale context for the conversion ");
        return AVERROR(EINVAL);
    }
    return 0;
}

int IAMedia::init_converted_image(uint8_t ***converted_input_samples, int **line_size, int width, int height, enum AVPixelFormat format) {
    if (!(*converted_input_samples = (uint8_t **)calloc(4, sizeof(**converted_input_samples)))) {
        fprintf(stderr, "Could not allocate converted input sample pointers\n");
        return AVERROR(ENOMEM);
    }
    if (!(*line_size = (int *)calloc(4, sizeof(int)))) {
        fprintf(stderr, "Could not allocate converted input sample pointers\n");
        return AVERROR(ENOMEM);
    }
    if (av_image_alloc(*converted_input_samples, *line_size, width, height, format, 1) < 0) {
        fprintf(stderr, "Could not allocate source image\n");
        return -1;
    }
    return 0;
}

int IAMedia::convert_image(const uint8_t **input_data, int *linesize1, uint8_t **converted_data, int *linesize2, int width, int height) {
    if (sws_scale(_sws_ctx, (const uint8_t * const*)input_data, linesize1, 0, height, (uint8_t * const*)converted_data, linesize2) < 0) {
        fprintf(stderr, "Could not scale video \n");
        return -1;
    }
    return 0;
}

int IAMedia::recode_media(const char *filename) {
    IAMedia::creat_media_file(filename);
    recodeFlag = true;
    return 0;
}

int IAMedia::creat_media_file(const char *filename) {
    int ret = 0;
    avformat_alloc_output_context2(&_ofmt_ctx, NULL, NULL, filename);
    if (!_ofmt_ctx) {
        fprintf(stderr, "Could not create output context\n");
        return AVERROR_UNKNOWN;
    }
    
    IAMedia::recode_newStream(_video_stream);
    IAMedia::recode_newStream(_audio_stream);
    
    av_dump_format(_ofmt_ctx, 0, filename, 1);
    
    if (!(_ofmt_ctx->oformat->flags & AVFMT_NOFILE)) {
        ret = avio_open(&_ofmt_ctx->pb, filename, AVIO_FLAG_WRITE);
        if (ret < 0) {
            fprintf(stderr, "Could not open output file '%s'", filename);
            return -1;
        }
    }
    ret = avformat_write_header(_ofmt_ctx, NULL);
    if (ret < 0) {
        fprintf(stderr, "Error occurred when opening output file\n");
        return AVERROR_UNKNOWN;
    }
    _pre_v_pts = -1;
    _pre_a_pts = -1;
    return 0;
}

int IAMedia::recode_newStream(AVStream *stream) {
    AVStream *out_stream;
    out_stream = avformat_new_stream(_ofmt_ctx, NULL);
    if (!out_stream) {
        fprintf(stderr, "Failed allocating output stream\n");
        return AVERROR_UNKNOWN;
    }
    if (avcodec_parameters_copy(out_stream->codecpar, stream->codecpar) < 0) {
        fprintf(stderr, "Failed allocating output stream\n");
        return AVERROR_UNKNOWN;
    }
    out_stream->codecpar->codec_tag = 0;
    return 0;
}

int IAMedia::save_recode_pkg(AVPacket *pkg, AVStream *stream) {
    AVPacket opkg = {};
    AVStream *out_stream = _ofmt_ctx->streams[pkg->stream_index];
    opkg.flags = pkg->flags;
    opkg.data = pkg->data;
    opkg.size = pkg->size;
    opkg.stream_index = pkg->stream_index;
    opkg.pts = pkg->pts;
    opkg.dts = pkg->dts;
    opkg.duration = pkg->duration;
    opkg.duration = av_rescale_q_rnd(opkg.duration, stream->time_base, out_stream->time_base, (AVRounding)(AV_ROUND_NEAR_INF | AV_ROUND_PASS_MINMAX));
    opkg.pts=av_rescale_q_rnd(opkg.pts, stream->time_base, out_stream->time_base, (AVRounding)(AV_ROUND_NEAR_INF | AV_ROUND_PASS_MINMAX));
    if (opkg.stream_index == _audio_stream_idx) {
        if (_pre_a_pts == -1) {
            _pre_a_pts = opkg.pts;
        }
        opkg.pts -= _pre_a_pts;
    } else {
        if (_pre_v_pts == -1) {
            _pre_v_pts = opkg.pts;
        }
        opkg.pts -= _pre_v_pts;
    }
    opkg.dts=opkg.pts;
    opkg.pos = -1;
    printf("pts == %d, size == %d, stream = %d \n", opkg.side_data_elems, opkg.size, opkg.stream_index);
    int ret = av_interleaved_write_frame(_ofmt_ctx, &opkg);
    if (ret < 0) {
        fprintf(stderr, "Error muxing packet\n");
        return ret;
    }
    return 0;
}

int IAMedia::stop_recode_media() {
    recodeFlag = false;
    av_write_trailer(_ofmt_ctx);
    avformat_close_input(&_ofmt_ctx);
    if (_ofmt_ctx && !(_ofmt_ctx->oformat->flags & AVFMT_NOFILE))
        avio_closep(&_ofmt_ctx->pb);
    avformat_free_context(_ofmt_ctx);
    printf("stop recode mp4");
    return 0;
}


int IAMedia::download_Media(const char *filename) {
    string f = filename;
    f = f + ".st";
    if((_ff = fopen(f.data(), "ab+")) == NULL)
        return -1;
    downloadFlag = true;
    return 0;
}

int IAMedia::stop_download_Media(const char *filename, bool iscontinue) {
    if (IAMedia::creat_media_file(filename) < 0) {
        return -1;
    }
    downloadFlag = false;
    fclose(_ff);
    
    string f = filename;
    f = f + ".st";
    FILE *ff = NULL;
    if((ff = fopen(f.data(), "rb")) == NULL)
        return -1;
    
    struct stat statbuf;
    stat(f.data(),&statbuf);
    long long size = statbuf.st_size;
    
    AVPacket ipkt = {};
    int s = 0, step = 0, count = 0;
    long long pts = 0, dts = 0, duration = 0;
    char flag = 0, key_flag = 0;
    bool finishFlag = false;
    while (step > 6 || size > s) {
        fseek(ff, s, 0);
        switch (step) {
            case 0: {
                if (fread(&flag, 1, 1, ff) < 1) {
                    finishFlag = true;
                    break;
                }
                s += 1;
                step += 1;
                break;
            }
            case 1: {
                fread(&key_flag, 1, 1, ff);
                s += 1;
                step += 1;
                break;
            }
            case 2: {
                fread(&count, 1, 4, ff);
                count = ntohl(count);
                s += 4;
                step += 1;
                break;
            }
            case 3: {
                uint8_t *data = NULL;
                data = (uint8_t *)calloc(count, sizeof(uint8_t));
                fread(data, 1, count, ff);
                ipkt.size = count;
                ipkt.data = data;
                s += count;
                step += 1;
                break;
            }
            case 4: {
                fread(&duration, 1, 8, ff);
                duration = ntohll(duration);
                s += 8;
                step += 1;
                break;
            }
            case 5: {
                fread(&dts, 1, 8, ff);
                dts = ntohll(dts);
                s += 8;
                step += 1;
                break;
            }
            case 6: {
                fread(&pts, 1, 8, ff);
                pts = ntohll(pts);
                s += 8;
                step += 1;
                break;
            }
            default: {
                ipkt.dts = dts;
                ipkt.pts = pts;
                ipkt.flags = key_flag;
                ipkt.duration = duration;
                ipkt.stream_index = flag;
                IAMedia::save_recode_pkg(&ipkt, ipkt.stream_index == _audio_stream_idx ? _audio_stream : _video_stream);
                step = 0;
                free(ipkt.data);
                break;
            }
        }
    }
    fclose(ff);
    av_write_trailer(_ofmt_ctx);
    avformat_close_input(&_ofmt_ctx);
    if (_ofmt_ctx && !(_ofmt_ctx->oformat->flags & AVFMT_NOFILE))
        avio_closep(&_ofmt_ctx->pb);
    avformat_free_context(_ofmt_ctx);
    return 0;
}

int IAMedia::save_download_st(AVPacket *pkg, AVStream *stream) {
    uint8_t *data = NULL;
    char flag = pkg->stream_index;
    char key_flag = pkg->flags;
    int ds = pkg->size;
    int size = ds + 8*3 + 6;
    printf("pts == %lld, size == %d, stream = %d d = %lld da = %d \n", pkg->pts, pkg->size, pkg->stream_index, pkg->duration, pkg->data[0]);
    data = (uint8_t *)calloc(size, sizeof(uint8_t));
    
    memcpy(data, &flag, 1);
    
    memcpy(data+1, &key_flag, 1);

    int a = htonl(ds);
    memcpy(data+2, &a, 4);
    
    memcpy(data+2+4, pkg->data, ds);
    
    long long d = htonll(pkg->duration);
    memcpy(data+2+4+ds, &d, 8);
    
    long long c = htonll(pkg->dts);
    memcpy(data+2+4+ds+8, &c, 8);
    
    long long b = htonll(pkg->pts);
    memcpy(data+2+4+ds+8+8, &b, 8);
    
    fwrite(data, 1, size, _ff);
    free(data);
    return 0;
}

int IAMedia::refleshFrame() {
    if (_audio_fifo->size > 0 && _video_fifo->size > 0 && _audio_fifo->fist->pts < _video_fifo->last->pts) {
        printf("_time == %d(%f)--- %d(%f) \n", _audio_fifo->size, _audio_fifo->fist->pts, _video_fifo->size, _video_fifo->fist->pts);
        YLFiFOData *e = NULL;
        pop_fifo(&_audio_fifo, &e);
        double pts = e->pts;
        if (IAMedia::renderData) {
            (*IAMedia::renderData)(e->buf, e->linesize, e->width);
        }
        free(e->buf);
        free(e);
        while (_video_fifo->size > 0 && _video_fifo->fist->pts < pts) {
            pop_fifo(&_video_fifo, &e);
            if (e) {
                if (IAMedia::renderRGB) {
                    (*IAMedia::renderRGB)(e->buf, e->linesize, e->width, e->heigth);
                }
                printf("_time = %f --- %f \n", pts, e->pts);
                free(e->buf);
                free(e);
            }
        }
        return 0;
    }
    return -1;
}




