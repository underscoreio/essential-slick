This is an [AsciiDoc](http://asciidoctor.org/docs/asciidoc-syntax-quick-reference/) document.

To convert it to HTML:

    $ gem install asciidoctor

    $ asciidoctor index.asciidoc
    $ open index.html 

To convert to PDF, well, [there are instructions for that](https://github.com/asciidoctor/asciidoctor-fopub/blob/master/README.adoc).
   
To enable [live preview](http://asciidoctor.org/docs/editing-asciidoc-with-live-preview/):

    $ gem install guard guard-shell rb-inotify
        
    $ guard start

...but I couldn't get that to work.

There is an AsciiDoc mode for Sublime Text.
