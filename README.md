This is an [AsciiDoc](http://asciidoctor.org/docs/asciidoc-syntax-quick-reference/) document.

To convert it to HTML:

    $ gem install asciidoctor

    $ asciidoctor index.asciidoc
    $ open index.html 
   
To enable [live preview](http://asciidoctor.org/docs/editing-asciidoc-with-live-preview/):

    $ gem install guard guard-shell rb-inotify
        
    $ guard start

There is an AsciiDoc mode for Sublime Text.
