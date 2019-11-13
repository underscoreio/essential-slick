lazy val root = project.in(file(".")).enablePlugins(TutPlugin)

tutSourceDirectory := sourceDirectory.value / "pages"

tutTargetDirectory := target.value / "pages"

scalaVersion := "2.13.0"

// Adapted from: https://tpolecat.github.io/2017/04/25/scalac-flags.html
scalacOptions ++= Seq(
  "-deprecation",                      // Emit warning and location for usages of deprecated APIs.
  "-encoding", "utf-8",                // Specify character encoding used by source files.
  "-explaintypes",                     // Explain type errors in more detail.
  "-feature",                          // Emit warning and location for usages of features that should be imported explicitly.
  "-language:existentials",            // Existential types (besides wildcard types) can be written and inferred
  "-language:experimental.macros",     // Allow macro definition (besides implementation and application)
  "-language:higherKinds",             // Allow higher-kinded types
  "-language:implicitConversions",     // Allow definition of implicit functions called views
  "-unchecked",                        // Enable additional warnings where generated code depends on assumptions.
  "-Xcheckinit",                       // Wrap field accessors to throw an exception on uninitialized access.
  "-Xfatal-warnings",                  // Fail the compilation if there are any warnings.
)

libraryDependencies ++= Seq(
  "com.typesafe.slick" %% "slick"           % "3.3.2",
  "com.typesafe.slick" %% "slick-hikaricp"  % "3.3.2",
  "com.h2database"      % "h2"              % "1.4.200",
  "ch.qos.logback"      % "logback-classic" % "1.2.3",
  "joda-time"           % "joda-time"       % "2.10.5",
  "org.joda"            % "joda-convert"    % "2.2.1"
)

lazy val pdf = taskKey[Unit]("Builds the PDF version of the book")
lazy val pdfPreview = taskKey[Unit]("Builds the PDF preview of the book")
lazy val html = taskKey[Unit]("Build the HTML version of the book")
lazy val epub = taskKey[Unit]("Build the ePub version of the book")

import sys.process._
pdf  := { tutQuick.value ; "grunt pdf" ! }
pdfPreview  := { tutQuick.value ; "grunt pandoc:pdf:preview" ! }
html := { tutQuick.value ; "grunt html" ! }
epub := { tutQuick.value ; "grunt epub" ! }

