# PDF文本选择、复制、高亮嵌入功能实现

## 底层

- 根据mupdf.dart文件，目前可以获得block、line、text的坐标

### 对应的核心底层C代码

```c
MUPDF_API MuPdfTextPage* mupdf_page_get_stext(MuPdfContext* ctx, MuPdfDocument* doc,
                                               int page_number) {
    if (!ctx || !doc) return NULL;

    fz_page* page = NULL;
    fz_stext_page* stext_page = NULL;
    fz_device* dev = NULL;
    MuPdfTextPage* result = NULL;

    /* MuPDF API 调用放在 fz_try 中（可能 longjmp） */
    fz_try(ctx->ctx) {
        page = fz_load_page(ctx->ctx, doc->doc, page_number);
        stext_page = fz_new_stext_page(ctx->ctx, fz_empty_rect);

        fz_stext_options opts = { 0 };
        opts.flags = FZ_STEXT_PRESERVE_WHITESPACE;

        dev = fz_new_stext_device(ctx->ctx, stext_page, &opts);
        fz_run_page(ctx->ctx, page, dev, fz_identity, NULL);
        fz_close_device(ctx->ctx, dev);
        fz_drop_device(ctx->ctx, dev);
        dev = NULL;
    } fz_catch(ctx->ctx) {
        snprintf(ctx->last_error, sizeof(ctx->last_error), "%s", fz_caught_message(ctx->ctx));
        if (dev) fz_drop_device(ctx->ctx, dev);
        if (stext_page) fz_drop_stext_page(ctx->ctx, stext_page);
        if (page) fz_drop_page(ctx->ctx, page);
        return NULL;
    }

    /* 数据转换在 fz_try 外部进行，避免 longjmp 导致 malloc 泄漏 */
    {
        int block_count = 0;
        int* line_counts = NULL;

        /* 第一遍：统计文本块数 */
        for (fz_stext_block* blk = stext_page->first_block; blk; blk = blk->next) {
            if (blk->type == FZ_STEXT_BLOCK_TEXT)
                block_count++;
        }

        if (block_count == 0) {
            result = (MuPdfTextPage*)calloc(1, sizeof(MuPdfTextPage));
            goto done;
        }

        /* 统计每个块的行数 */
        line_counts = (int*)calloc((size_t)block_count, sizeof(int));
        if (!line_counts) {
            snprintf(ctx->last_error, sizeof(ctx->last_error), "out of memory");
            goto done;
        }

        {
            int bi = 0;
            for (fz_stext_block* blk = stext_page->first_block; blk; blk = blk->next) {
                if (blk->type != FZ_STEXT_BLOCK_TEXT) continue;
                for (fz_stext_line* ln = blk->u.t.first_line; ln; ln = ln->next)
                    line_counts[bi]++;
                bi++;
            }
        }

        /* 分配顶层结构 */
        result = (MuPdfTextPage*)calloc(1, sizeof(MuPdfTextPage));
        if (!result) {
            free(line_counts);
            snprintf(ctx->last_error, sizeof(ctx->last_error), "out of memory");
            goto done;
        }

        result->blocks_count = block_count;
        result->blocks = (MuPdfTextBlock*)calloc((size_t)block_count, sizeof(MuPdfTextBlock));
        if (!result->blocks) {
            free(line_counts);
            mupdf_stext_page_free(result);
            result = NULL;
            snprintf(ctx->last_error, sizeof(ctx->last_error), "out of memory");
            goto done;
        }

        /* 第二遍：填充数据 */
        {
            int bi = 0;
            for (fz_stext_block* blk = stext_page->first_block; blk; blk = blk->next) {
                if (blk->type != FZ_STEXT_BLOCK_TEXT) continue;

                MuPdfTextBlock* tb = &result->blocks[bi];
                tb->bbox.x0 = blk->bbox.x0;
                tb->bbox.y0 = blk->bbox.y0;
                tb->bbox.x1 = blk->bbox.x1;
                tb->bbox.y1 = blk->bbox.y1;
                tb->lines_count = line_counts[bi];
                tb->lines = (MuPdfTextLine*)calloc((size_t)line_counts[bi], sizeof(MuPdfTextLine));
                if (!tb->lines) {
                    free(line_counts);
                    mupdf_stext_page_free(result);
                    result = NULL;
                    snprintf(ctx->last_error, sizeof(ctx->last_error), "out of memory");
                    goto done;
                }

                int li = 0;
                for (fz_stext_line* ln = blk->u.t.first_line; ln; ln = ln->next) {
                    MuPdfTextLine* tl = &tb->lines[li];

                    tl->bbox.x0 = ln->bbox.x0;
                    tl->bbox.y0 = ln->bbox.y0;
                    tl->bbox.x1 = ln->bbox.x1;
                    tl->bbox.y1 = ln->bbox.y1;

                    /* 统计字符数 */
                    int ch_count = 0;
                    for (fz_stext_char* ch = ln->first_char; ch; ch = ch->next)
                        ch_count++;

                    tl->chars_count = ch_count;
                    tl->chars = (MuPdfTextChar*)calloc((size_t)ch_count, sizeof(MuPdfTextChar));
                    tl->text = (char*)calloc((size_t)(ch_count * 4 + 1), 1);

                    if (!tl->chars || !tl->text) {
                        free(line_counts);
                        mupdf_stext_page_free(result);
                        result = NULL;
                        snprintf(ctx->last_error, sizeof(ctx->last_error), "out of memory");
                        goto done;
                    }

                    /* 填充字符数据 */
                    int ci = 0;
                    size_t text_pos = 0;
                    for (fz_stext_char* ch = ln->first_char; ch; ch = ch->next) {
                        MuPdfTextChar* tc = &tl->chars[ci];

                        fz_rect r = fz_rect_from_quad(ch->quad);
                        tc->bbox.x0 = r.x0;
                        tc->bbox.y0 = r.y0;
                        tc->bbox.x1 = r.x1;
                        tc->bbox.y1 = r.y1;

                        int bytes = unicode_to_utf8(ch->c, tc->utf8);
                        if (bytes > 0) {
                            memcpy(tl->text + text_pos, tc->utf8, (size_t)bytes);
                            text_pos += (size_t)bytes;
                        }
                        ci++;
                    }
                    tl->text[text_pos] = '\0';
                    li++;
                }
                bi++;
            }
        }
        free(line_counts);
    }

done:
    if (page) fz_drop_page(ctx->ctx, page);
    if (stext_page) fz_drop_stext_page(ctx->ctx, stext_page);

    return result;
}
```

## 中间层

mupdf.dart中已实现必要接口

## UI

为了实现上述功能，目前暂定三层实现

+---------------------------------------------------+
|  GestureDetector (捕获手指 Start 和 Current 坐标)   |
+---------------------------------------------------+
|  CustomPaint     (将选中的字符按行合并成几条矩形绘制) |
+---------------------------------------------------+
|  RawImage        (MuPDF 渲染的底层底图)            |

- 也可能有其他的方案？如果有更好的方案，可以提出


### 坐标映射

手势在 Flutter Widget 上的坐标点（比如 Offset(100, 200)），需要根据当前图片在屏幕上的实际缩放比例，和MuPDF 的内部坐标系进行转换（PdfRect 的坐标系）


### 流式选择算法

当手指从点 A 拖到点 B 时：

根据点 A 找到距离最近的起始字符（记为 startIndex）。

根据点 B 找到距离最近的结束字符（记为 endIndex）

### 合并绘制

将选中的字符，按照line（必要时可能不需要参考block）的范围，对包围盒交集进行绘制


## 优化

由于 PDF 的字符大多是从上往下、从左往右排布的。当手指拖动时，不需要每次都遍历整页的所有字符。可以利用 y0 坐标对 lines 进行二分查找 (Binary Search)，迅速定位手指落在哪一行，将查找复杂度从 $O(N)$ 降到 $O(\log N)$。

## 高亮与嵌入保存

- 待定
- 赞不实现