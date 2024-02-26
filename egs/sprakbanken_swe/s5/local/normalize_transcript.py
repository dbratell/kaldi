#!/usr/bin/env python3
import sys
import re


## Global vars

normdict = {".": "",
            ",": "",
            ":": "",
            ";": "",
            "?": "",
            "!": "",
            "\\": " ",
            "\t": " "
            }
#removes all the above signs

## Main

with open(sys.argv[1], "r", encoding="utf8") as transcript:
    with open(sys.argv[2], "w", encoding="utf8") as outtext:

        #TODO: Add number normalisation and remove uppercasing

        for line in transcript:
            line = line.replace(".\Punkt", ".")
            line = line.replace(",\Komma", ",")
            # TODO: This combined with a lack of line ending
            # made some words become concatenated. Replace with
            # a space and add a newline below.
            normtext1 = re.sub(r'[\.,:;\?!]', ' ', line)
            normtext2 = re.sub(r'[\t\\]', ' ', normtext1)
            normtext3 = re.sub(r'  +', ' ', normtext2.strip())
            outtext.write(normtext3.upper() + "\n")
