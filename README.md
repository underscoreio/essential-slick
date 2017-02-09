Essential Slick
--------------

Getting Started
---------------

You need to have installed docker. Then...

~~~
$ ./go.sh
$ npm install
$ sbt
sbt> pdf
~~~

To avoid running out of MetaSpace you'll also maybe want to:

```
export JAVA_OPTS="-Xmx3g -XX:+TieredCompilation -XX:ReservedCodeCacheSize=256m -XX:+UseNUMA -XX:+UseParallelGC -XX:+CMSClassUnloadingEnabled"
```

For upgrading:

~~~
rm -rf node_modules
npm install
~~~

Writing
-------

The source files are in _src/pages_.  Scala blocks are executed by tut when marked as:

```tut:book
your code here
```

Note:

- no space before tut in the code block
- `~~~tut` isn't recognized by tut

For each chapter you'll need to update _src/main/rsources/application.conf_ to include the chapter database configuration.

The tut converted sources are output to _target/pages_.

The `dist` directory contains the PDF etc.

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
