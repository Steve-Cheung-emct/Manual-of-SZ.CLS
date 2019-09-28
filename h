latexmk -c
uplatex main-h.tex
ptex2pdf -l -u  -ot "-kanji=utf8 " main-h.tex
rm -f *.aux *.bak *.log *.bbl *.blg *.thm *.toc *.out *.lof *.lol *.lot *.ent *.fdb_latexmk *.synctex.gz

cd "/c/Program Files (x86)/Adobe/Acrobat 11.0/Acrobat"
./Acrobat.exe "D:\20190522\Cygwin64\sz\main-h.pdf"

