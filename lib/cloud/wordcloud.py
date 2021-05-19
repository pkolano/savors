#!/usr/bin/env python
# Author: Andreas Christian Mueller <amueller@ais.uni-bonn.de>
# (c) 2012
#
# License: MIT

import random

from PIL import Image
from PIL import ImageDraw
from PIL import ImageFont
from StringIO import StringIO

import numpy as np
from query_integral_image import query_integral_image

FONT_PATH = "/Library/Fonts/Times New Roman.ttf"


def make_wordcloud(words, counts, colors, font_path=None,
                   width=400, height=200, margin=5, ranks_only=False):
    """Build word cloud using word counts, store in image.

    Parameters
    ----------
    words : numpy array of strings
        Words that will be drawn in the image.

    counts : numpy array of word counts
        Word counts or weighting of words. Determines the size of the word in
        the final image.
        Will be normalized to lie between zero and one.

    font_path : string
        Font path to the font that will be used.
        Defaults to DroidSansMono path.

    width : int (default=400)
        Width of the word cloud image.

    height : int (default=200)
        Height of the word cloud image.

    ranks_only : boolean (default=False)
        Only use the rank of the words, not the actual counts.

    Notes
    -----
    Larger Images with make the code significantly slower.
    If you need a large image, you can try running the algorithm at a lower
    resolution and then drawing the result at the desired resolution.

    In the current form it actually just uses the rank of the counts,
    i.e. the relative differences don't matter.
    Play with setting the font_size in the main loop vor differnt styles.

    Colors are used completely at random. Currently the colors are sampled
    from HSV space with a fixed S and V.
    Adjusting the percentages at the very end gives differnt color ranges.
    Obviously you can also set all at random - haven't tried that.

    """
    if len(counts) <= 0:
        print("We need at least 1 word to plot a word cloud, got %d."
              % len(counts))

    if font_path is None:
        font_path = FONT_PATH

    # normalize counts
    counts = counts / float(counts.max())
    # sort words by counts
    inds = np.argsort(counts)[::-1]
    counts = counts[inds]
    colors = colors[inds]
    words = words[inds]
    # create image
    img_grey = Image.new("L", (width, height))
    draw = ImageDraw.Draw(img_grey)
    integral = np.zeros((height, width), dtype=np.uint32)
    img_array = np.asarray(img_grey)
    font_sizes, positions, orientations = [], [], []
    # intitiallize font size "large enough"
    font_size = 1000
    # start drawing grey image
    for word, count in zip(words, counts):
        # alternative way to set the font size
        if not ranks_only:
            font_size = min(font_size, int(100 * np.log(count + 100)))
        while True:
            # try to find a position
            font = ImageFont.truetype(font_path, font_size)
            # transpose font optionally
            orientation = random.choice([None, Image.ROTATE_90])
            transposed_font = ImageFont.TransposedFont(font,
                                                       orientation=orientation)
            draw.font = transposed_font
            # get size of resulting text
            box_size = draw.textsize(word)
            # find possible places using integral image:
            result = query_integral_image(integral, box_size[1] + margin,
                                          box_size[0] + margin)
            if result is not None or font_size == 0:
                break
            # if we didn't find a place, make font smaller
            font_size -= 1

        if font_size == 0:
            # we were unable to draw any more
            break

        x, y = np.array(result) + margin // 2
        # actually draw the text
        draw.text((y, x), word, fill="white")
        positions.append((x, y))
        orientations.append(orientation)
        font_sizes.append(font_size)
        # recompute integral image
        img_array = np.asarray(img_grey)
        # recompute bottom right
        # the order of the cumsum's is important for speed ?!
        partial_integral = np.cumsum(np.cumsum(img_array[x:, y:], axis=1),
                                     axis=0)
        # paste recomputed part into old image
        # if x or y is zero it is a bit annoying
        if x > 0:
            if y > 0:
                partial_integral += (integral[x - 1, y:]
                                     - integral[x - 1, y - 1])
            else:
                partial_integral += integral[x - 1, y:]
        if y > 0:
            partial_integral += integral[x:, y - 1][:, np.newaxis]

        integral[x:, y:] = partial_integral

    # redraw in color
    img = Image.new("RGB", (width, height))
    draw = ImageDraw.Draw(img)
    everything = zip(words, colors, font_sizes, positions, orientations)
    for word, color, font_size, position, orientation in everything:
        font = ImageFont.truetype(font_path, font_size)
        # transpose font optionally
        transposed_font = ImageFont.TransposedFont(font,
                                                   orientation=orientation)
        draw.font = transposed_font
        color = "#" + color
        draw.text((position[1], position[0]), word, fill=color)
                  #fill="hsl(%d" % random.randint(0, 255) + ", 80%, 50%)")
    #img.show()
    sio = StringIO()
    img.save(sio, format="PNG")
    print sio.getvalue()


if __name__ == "__main__":

    import os
    import sys

    random.seed(1);
    lines = sys.stdin.readlines()
    text = "".join(lines)

    counts,colors,words = np.loadtxt(StringIO(text),
                              dtype=[('n', 'L'),('c','O'),('w','O')],
                              delimiter=',', usecols=(0,1,2), unpack=True)
    counts = make_wordcloud(words, counts, colors,
                            width=int(sys.argv[1]), height=int(sys.argv[2]),
                            font_path=sys.argv[3])
