#ifndef FFMPEG_VERSION_COMPAT_H
#define FFMPEG_VERSION_COMPAT_H

extern "C" {
#include <libavutil/frame.h>
#include <libavutil/version.h>
}

#if LIBAVUTIL_VERSION_MAJOR >= 58

#if LIBAVUTIL_VERSION_MAJOR >= 60
#define FFMPEG_HAS_PTS_AFTER_BEST_EFFORT 1
#endif

#if !defined(FF_API_FRAME_PKT) || FF_API_FRAME_PKT
#define FFMPEG_HAS_BEST_EFFORT_TIMESTAMP 1
#endif

#if !defined(FF_API_REORDERED_OPAQUE) || FF_API_REORDERED_OPAQUE
#define FFMPEG_HAS_REORDERED_OPAQUE 1
#endif

#endif

#ifndef FFMPEG_HAS_BEST_EFFORT_TIMESTAMP
#define FFMPEG_HAS_BEST_EFFORT_TIMESTAMP 1
#endif

static inline int64_t get_frame_best_effort_timestamp(const AVFrame *frame) {
#if FFMPEG_HAS_BEST_EFFORT_TIMESTAMP
    return frame->best_effort_timestamp;
#else
    return AV_NOPTS_VALUE;
#endif
}

static inline int64_t get_frame_pts(const AVFrame *frame) {
#if FFMPEG_HAS_PTS_AFTER_BEST_EFFORT
    return frame->pts;
#else
    return frame->pts;
#endif
}

#endif
