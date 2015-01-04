#global module:false

path    = require 'path'
process = require 'child_process'

"use strict"

module.exports = (grunt) ->
  minify = grunt.option('minify') ? false

  grunt.loadNpmTasks "grunt-browserify"
  grunt.loadNpmTasks "grunt-contrib-connect"
  grunt.loadNpmTasks "grunt-contrib-less"
  grunt.loadNpmTasks "grunt-contrib-watch"
  grunt.loadNpmTasks "grunt-exec"
  grunt.loadNpmTasks "grunt-css-url-embed"

  joinLines = (lines) ->
    lines.split(/[ \r\n]+/).join(" ")

  pandocSources = joinLines """
    src/pages/intro/index.md
    src/pages/intro/conventions.md
    src/pages/basics/index.md
    src/pages/basics/actions.md
    src/pages/basics/routes.md
    src/pages/basics/requests.md
    src/pages/basics/results.md
    src/pages/basics/failure.md
    src/pages/links.md
  """

  grunt.initConfig
    less:
      main:
        options:
          paths: [
            "node_modules"
            "src/css"
          ]
          compress: minify
          yuicompress: minify
        files:
          "dist/temp/main.noembed.css" : "src/css/main.less"

    cssUrlEmbed:
      main:
        options:
          baseDir: "."
        files:
          "dist/temp/main.css" : "dist/temp/main.noembed.css"

    browserify:
      main:
        src:  "src/js/main.coffee"
        dest: "dist/temp/main.js"
        cwd:  "."
        options:
          watch: false
          transform: if minify
            [ 'coffeeify', [ 'uglifyify', { global: true } ] ]
          else
            [ 'coffeeify' ]
          browserifyOptions:
            debug: false
            extensions: [ '.coffee' ]

    watchImpl:
      options:
        livereload: true
      css:
        files: [
          "src/css/**/*"
        ]
        tasks: [
          "less"
          "cssUrlEmbed"
          "pandoc:html"
        ]
      js:
        files: [
          "src/js/**/*"
        ]
        tasks: [
          "browserify"
          "pandoc:html"
        ]
      templates:
        files: [
          "src/templates/**/*"
        ]
        tasks: [
          "pandoc:html"
          "pandoc:pdf"
          "pandoc:epub"
        ]
      pages:
        files: [
          "src/pages/**/*"
        ]
        tasks: [
          "pandoc:html"
          "pandoc:pdf"
          "pandoc:epub"
        ]
      metadata:
        files: [
          "src/meta/**/*"
        ]
        tasks: [
          "pandoc:html"
          "pandoc:pdf"
          "pandoc:epub"
        ]

    connect:
      server:
        options:
          port: 4000
          base: 'dist'

  grunt.renameTask "watch", "watchImpl"

  grunt.registerTask "pandoc", "Run pandoc", (target) ->
    done = this.async()

    target ?= "html"

    switch target
      when "pdf"
        output   = "--output=dist/essential-slick.pdf"
        template = "--template=src/templates/template.tex"
        filters  = joinLines """
                     --filter=src/filters/pdf/callout.coffee
                     --filter=src/filters/pdf/columns.coffee
                   """
        metadata = "src/meta/pdf.yaml"

      when "html"
        output   = "--output=dist/essential-slick.html"
        template = "--template=src/templates/template.html"
        filters  = joinLines """
                     --filter=src/filters/html/tables.coffee
                   """
        metadata = "src/meta/html.yaml"

      when "epub"
        output   = "--output=dist/essential-slick.epub"
        template = "--epub-stylesheet=dist/temp/main.css"
        filters  = ""
        metadata = "src/meta/epub.yaml"

      when "json"
        output   = "--output=dist/essential-slick.json"
        template = ""
        filters  = ""
        metadata = ""

      else
        grunt.log.error("Bad pandoc format: #{target}")

    command = joinLines """
      pandoc
      --smart
      #{output}
      #{template}
      --from=markdown+grid_tables+multiline_tables+fenced_code_blocks+fenced_code_attributes+yaml_metadata_block+implicit_figures
      --latex-engine=xelatex
      #{filters}
      --chapters
      --number-sections
      --table-of-contents
      --highlight-style tango
      --standalone
      --self-contained
      src/meta/metadata.yaml
      --epub-cover-image=src/images/epub_cover.png
      #{metadata}
      #{pandocSources}
    """

    grunt.log.error("Running: #{command}")

    pandoc = process.exec(command)

    pandoc.stdout.on 'data', (d) ->
      grunt.log.write(d)
      return

    pandoc.stderr.on 'data', (d) ->
      grunt.log.error(d)
      return

    pandoc.on 'error', (err) ->
      grunt.log.error("Failed with: #{err}")
      done(false)

    pandoc.on 'exit', (code) ->
      if code == 0
        grunt.verbose.subhead("pandoc exited with code 0")
        done()
      else
        grunt.log.error("pandoc exited with code #{code}")
        done(false)

    return

  grunt.registerTask "json", [
    "pandoc:json"
  ]

  grunt.registerTask "html", [
    "less"
    "cssUrlEmbed"
    "browserify"
    "pandoc:html"
  ]

  grunt.registerTask "pdf", [
    "pandoc:pdf"
  ]

  grunt.registerTask "epub", [
    "less"
    "cssUrlEmbed"
    "pandoc:epub"
  ]

  grunt.registerTask "all", [
    "less"
    "cssUrlEmbed"
    "browserify"
    "pandoc:html"
    "pandoc:pdf"
    "pandoc:epub"
  ]

  grunt.registerTask "zip", [
    "all"
    "exec:exercises"
    "exec:zip"
  ]

  grunt.registerTask "serve", [
    "build"
    "connect:server"
    "watchImpl"
  ]

  grunt.registerTask "watch", [
    "all"
    "connect:server"
    "watchImpl"
    "serve"
  ]

  grunt.registerTask "default", [
    "zip"
  ]
