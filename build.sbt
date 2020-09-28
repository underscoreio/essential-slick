lazy val root = project
  .in(file("."))
  .enablePlugins(MdocPlugin)
  .settings(
    mdocIn := sourceDirectory.value / "pages",
    mdocOut := target.value / "pages",
    scalaVersion := "2.13.1",
    version := "3.0.0",
    libraryDependencies ++= Seq(
      "com.typesafe.slick" %% "slick"           % "3.3.3",
      "com.typesafe.slick" %% "slick-hikaricp"  % "3.3.3",
      "com.h2database"      % "h2"              % "1.4.200",
      "ch.qos.logback"      % "logback-classic" % "1.2.3",
      "joda-time"           % "joda-time"       % "2.10.5",
      "org.joda"            % "joda-convert"    % "2.2.1"
    ),
    scalacOptions ++= Seq(
      "-deprecation",
      "-encoding", "utf-8",
      "-feature",
      "-language:existentials",
      "-language:experimental.macros",
      "-language:higherKinds",
      "-language:implicitConversions",
      "-unchecked",
      "-Xcheckinit",
      "-Xfatal-warnings",
    )
  )


lazy val pdf = taskKey[Unit]("Builds the PDF version of the book")
lazy val pdfPreview = taskKey[Unit]("Builds the PDF preview of the book")
lazy val html = taskKey[Unit]("Build the HTML version of the book")
lazy val epub = taskKey[Unit]("Build the ePub version of the book")

import sys.process._
pdf  := { mdoc.toTask("").value ; "grunt pdf" ! }
pdfPreview  := { mdoc.toTask("").value ; "grunt pandoc:pdf:preview" ! }
html := { mdoc.toTask("").value ; "grunt html" ! }
epub := { mdoc.toTask("").value ; "grunt epub" ! }
