Essential Slick
--------------

Getting Started
---------------

You'll need to install the grunt project dependencies the first time you check the project out:

~~~
brew install pandoc
npm install -g grunt-cli
npm install
~~~

For upgrading:

~~~
rm -rf node_modules
npm install
~~~

Building
--------

~~~
sbt pdf
~~~

Writing
-------

The source files are in _src/raw_.  Scala blocks are executed by tut when marked as:

```tut:book
your code here
```

Note:

- no space before tut in the code block
- `~~~tut` isn't recognized by tut

For each chapter you'll need to update _src/main/rsources/application.conf_ to include the chapter database configuration.

The tut converted sources are output to _src/pages_.

All other targets are placed in the `dist` directory.

Command reference
-----------------

Use the following commands if you need to build after tut has run:

~~~
grunt pdf
grunt html
grunt epub
~~~

All targets are placed in the `dist` directory.

Run the following to build all formats, start a web server to serve them all,
and rebuild if you change any files:

~~~
grunt watch
~~~

Use the following to build all a ZIP of all formats:

~~~
grunt zip
~~~

The default grunt behaviour is to run `zip`:

~~~
grunt
~~~

Publishing a Preview
--------------------

The `grunt` command generates `essential-scala-3-preview.pdf` but this does not include the full TOC.
To create a version of the preview with the full TOC:

~~~
$ cd  ..
$ git checkout https://github.com/d6y/toctastic
$ cd toctastic
$ sh eslick.sh
~~~

This will create `dist/essential-slick-3-preview-with-full-toc.pdf`.

Upload this file to the Underscore S3 account, in the `book-sample` bucket.
It should have world-read permissions on it.
Check that you can download it from the book page to be sure.
