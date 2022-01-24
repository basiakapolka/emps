#!/usr/bin/bash
#
# this script contains functions that produce Lantern's input and output files

# custom settings

output_filename='Clipperton_EMPS'
output_directory='public'
siteurl=''

# utilities

pandoc_command='pandoc --quiet' # change to 'pandoc --verbose' to debug

# setup

mkdir -p _temp/
mkdir -p $output_directory

# convert manuscript files to markdown

preprocess() {
    local docx_files=`ls -1 preprocess/*.docx 2>/dev/null | wc -l`
    local odt_files=`ls -1 preprocess/*.odt 2>/dev/null | wc -l`
    local latex_files=`ls -1 preprocess/*.tex 2>/dev/null | wc -l`

    if [ $docx_files != 0 ] ; then 
    for FILE in preprocess/*.docx
        do 
            $pandoc_command "$FILE" \
                --to markdown \
                --wrap=none \
                --extract-media=images \
                -standalone \
                --output "${FILE%.*}.md"
            mv "${FILE%.docx}.md" text/chapters/
        done
    fi

    if [ $odt_files != 0 ] ; then 
    for FILE in source/preprocess/*.odt
        do 
            $pandoc_command "$FILE" \
                --to markdown \
                --wrap=none \
                --extract-media=images \
                -standalone \
                --output "${FILE%.*}.md"
            mv "${FILE%.docx}.md" text/chapters/
        done
    fi

    if [ $latex_files != 0 ] ; then 
    for FILE in source/preprocess/*.tex
        do 
            $pandoc_command "$FILE" \
                --to markdown \
                --wrap=none \
                --extract-media=images \
                -standalone \
                --output "${FILE%.*}.md"
            mv "${FILE%.docx}.md" text/chapters/
        done
    fi
}

# lantern output formats

pdf_context() {
    # combine all markdown files into one
    $pandoc_command text/*.md -o _temp/chapters.md
    # convert markdown to ConTeXt
    $pandoc_command _temp/chapters.md \
        --to context \
        --defaults settings/context.yml \
        --output $output_directory/$output_filename.tex
    # convert ConTeXt to PDF    
    $pandoc_command _temp/chapters.md \
        --to context \
        --defaults settings/context.yml \
        --output $output_directory/$output_filename.pdf
    echo "📖 The PDF edition is now available in the $output_directory folder"
}

pdf_latex() {
    # combine all markdown files into one
    $pandoc_command text/*.md -o _temp/chapters.md
    # convert markdown to LaTeX
    $pandoc_command _temp/chapters.md \
        --to latex \
        --defaults settings/latex.yml \
        --output $output_directory/$output_filename.tex
    # convert LaTeX to PDF    
    $pandoc_command _temp/chapters.md \
        --to latex \
        --defaults settings/latex.yml \
        --output $output_directory/$output_filename.pdf
    echo "📖 The PDF edition is now available in the $output_directory folder"
}

docx() {
    $pandoc_command text/*.md -o _temp/chapters.md
    $pandoc_command _temp/chapters.md \
        --defaults settings/docx.yml \
        -o $output_directory/$output_filename.docx
    echo "📖 The DOCX edition is now available in the $output_directory folder"
}

epub() {
    $pandoc_command text/*.md -o _temp/chapters.md
    $pandoc_command _temp/chapters.md \
        --defaults settings/epub.yml \
        --resource-path=.:images \
        --mathml \
        --output $output_directory/$output_filename.epub
    echo "📖 The EPUB edition is now available in the $output_directory folder";
}

oai() {
    touch _temp/empty.txt
    $pandoc_command _temp/empty.txt \
        --to plain \
        --metadata-file metadata.yml \
        --template templates/oai.xml \
        -o $output_directory/$output_filename.xml
    echo "🌐 The OAI-PMH record is now available in the $output_directory folder"
}

markdown() {
    $pandoc_command text/*.md \
        --metadata-file metadata.yml \
        --wrap=none \
        -s -o $output_directory/$output_filename.md
    echo "📖 The Markdown file is now available in the $output_directory folder";
}

# these next set of functions help build the website

copy_assets() {
    echo "Copying assets..."
    if [ -d "images" ] 
    then
        echo "Copying images..."
        cp -r images $output_directory; 
    else
        echo "No images directory. Skipping..."
    fi 
    cp -r lib/css/ $output_directory;
    cp -r lib/js/ $output_directory;
}

extract_metadata() {
    echo "Extracting chapter metadata..."
    for FILE in text/*.md; do
        # sets the h1 markdown heading as the chapter title
        local chapter_title="$(grep '^# ' $FILE | sed 's/# //')"
        local basename="$(basename "$FILE" .md)"

        # assigns categories
        $pandoc_command "$FILE" \
            --metadata basename=$basename \
            --template templates/website/category.template.txt \
            --to html \
            --output "_temp/$basename.category.txt"

        # converts metadata to json
        $pandoc_command "$FILE" \
            --metadata chapter_title="$chapter_title" \
            --metadata htmlfile="$basename.html" \
            --template templates/website/metadata.template.json \
            --to html \
            --output "_temp/$basename.metadata.json"
    done;                  
}

build_chapter_index() {
    echo "Building the chapter index..."
    echo "{\"chapters\": [" > _temp/chapters.json
    local SEPARATOR=""
    for FILE in _temp/*.metadata.json; do
        printf '%s' "$SEPARATOR" >> _temp/chapters.json
        cat "$FILE" >> _temp/chapters.json
        SEPARATOR=","
    done
    echo "]}" >> _temp/chapters.json
}

build_index() {
    # consolidates the metadata into a single json file
    echo "Grouping metadata by category..."  # (yep, this #is a right mess)
    echo "{\"categories\": [" > _temp/index.json
    local SEPARATOR_OUTER=""  # no comma before first list element (categories)
    local SEPARATOR_INNER=""  # ditto (recipes per category)
    local IFS=$'\n'           # tell for loop logic to split on #newlines only, not spaces
    local CATS="$(cat _temp/*.category.txt)"
    for CATEGORY in $(echo "$CATS" | cut -d" " -f2- | sort | uniq); do
        printf '%s' "$SEPARATOR_OUTER" >> _temp/index.json
        local CATEGORY_FAUX_URLENCODED="$(echo "$CATEGORY" | awk -f "templates/website/faux_urlencode.awk")"

        # some explanation on the next line and similar ones: this uses `tee -a`
        # instead of `>>` to append to two files instead of one, but since we don't
        # actually want to see the output, pipe that to /dev/null
        printf '%s' "{\"category\": \"$CATEGORY\", \"category_faux_urlencoded\": \"$CATEGORY_FAUX_URLENCODED\", \"info\": [" | tee -a "_temp/index.json" "_temp/$CATEGORY_FAUX_URLENCODED.category.json" >/dev/null
        for C in $CATS; do
            BASENAME=$(echo "$C" | cut -d" " -f1)
            C_CAT=$(echo "$C" | cut -d" " -f2-)
            if [[ "$C_CAT" == "$CATEGORY" ]]; then
                printf '%s' "$SEPARATOR_INNER" | tee -a "_temp/index.json" "_temp/$CATEGORY_FAUX_URLENCODED.category.json" >/dev/null
                cat "_temp/$BASENAME.metadata.json" | tee -a "_temp/index.json" "_temp/$CHAPTER_FAUX_URLENCODED.category.json" > /dev/null
                SEPARATOR_INNER=","
            fi
        done
        printf "]}\n" | tee -a "_temp/index.json" "_temp/$CATEGORY_FAUX_URLENCODED.category.json" > /dev/null
        local SEPARATOR_OUTER=","
        local SEPARATOR_INNER=""
    done
    unset IFS
    echo "]}" >> _temp/index.json
}

html() {
    local TIME_START=$(date +%s)
    touch _temp/empty.txt
    copy_assets
    extract_metadata
    build_chapter_index
    build_index
    
    echo "Building chapter pages..."
    for FILE in text/*.md;do
        echo "⚙️ Processing $FILE..."
        local CATEGORY_FAUX_URLENCODED="$(cat "_temp/$(basename "$FILE" .md).category.txt" | cut -d" " -f2- | awk -f "templates/website/faux_urlencode.awk")"
        # when running under GitHub Actions, all file modification dates are set to
        # the date of the checkout (i.e., the date on which the workflow was
        # executed), so in that case, use the most recent commit date of each file
        # as its update date – you'll probably also want to set the TZ environment
        # variable to your local timezone in the workflow file (#21)
        if [[ "$GITHUB_ACTIONS" = true ]]; then
            local UPDATED_AT="$(git log -1 --date=short-local --pretty='format:%cd' "$FILE")"
        else
            local UPDATED_AT="$(date -r "$FILE" "+%Y-%m-%d")"
        fi
        
        local basename="$(basename "$FILE" .md)"
        $pandoc_command "$FILE" \
            --metadata-file _temp/chapters.json \
            --metadata siteurl=$siteurl \
            --metadata category_faux_urlencoded="$CATEGORY_FAUX_URLENCODED" \
            --metadata updatedtime="$UPDATED_AT" \
            --metadata htmlfile="$basename.html" \
            --defaults settings/html.yml \
            --output "$output_directory/$basename.html"
            
    done
   
    echo "Building the home page..."
    $pandoc_command _temp/empty.txt \
        --metadata-file _temp/chapters.json \
        --metadata-file metadata.yml \
        --metadata-file settings/config.yml \
        --template templates/website/home.html \
        --metadata updatedtime="$(date "+%Y-%m-%d")" \
        --standalone \
        --output $output_directory/index.html

    echo "Assembling search index..."
    echo "[" > _temp/search.json
    local SEPARATOR=""
    for FILE in _temp/*.metadata.json; do
        printf '%s' "$SEPARATOR" >> _temp/search.json
        cat "$FILE" >> _temp/search.json
        SEPARATOR=","
    done
    echo "]" >> _temp/search.json
    cp -r _temp/search.json $output_directory

    local TIME_END=$(date +%s)
    local TIME_TOTAL=$((TIME_END-TIME_START))
    echo "🚀 All done after $TIME_TOTAL seconds!"
}

reset() {
    rm -rf $output_directory
    rm -rf _temp
    echo "🗑️ Let's start over.";
}

server() {
    # runs a local development server for testing
    # requires Python 3.x installed on the machine
    html;
    python3 -m http.server --directory $output_directory;
}

all_formats() {
    epub
    docx
    oai
    pdf_latex # change to pdf_latex if using LaTeX
    html
}

# If no arguments are specified in the $ sh lantern.sh command,
# then run the textbook function (which builds all formats)
if [ -z "$1" ]
then
    all_formats
fi

"$@"