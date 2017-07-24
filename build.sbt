lazy val root = project.in(file("."))
  .settings(tutSettings)

tutSourceDirectory := sourceDirectory.value / "pages"

tutTargetDirectory := target.value / "pages"

scalaVersion := "2.12.1"

scalacOptions ++= Seq(
  "-deprecation",
  "-encoding", "UTF-8",
  "-unchecked",
  "-feature",
  "-Ywarn-dead-code",
  "-Xlint",
  "-Xfatal-warnings"
)

libraryDependencies ++= Seq(
  "com.typesafe.slick" %% "slick"           % "3.2.1",
  "com.typesafe.slick" %% "slick-hikaricp"  % "3.2.1",
  "com.h2database"      % "h2"              % "1.4.185",
  "ch.qos.logback"      % "logback-classic" % "1.1.2",
  "joda-time"           % "joda-time"       % "2.6",
  "org.joda"            % "joda-convert"    % "1.2"
)

lazy val pdf = taskKey[Unit]("Builds the PDF version of the book")
lazy val pdfPreview = taskKey[Unit]("Builds the PDF preview of the book")
lazy val html = taskKey[Unit]("Build the HTML version of the book")
lazy val epub = taskKey[Unit]("Build the ePub version of the book")

pdf  := { tutQuick.value ; "grunt pdf"  ! }
pdfPreview  := { tutQuick.value ; "grunt pandoc:pdf:preview"  ! }
html := { tutQuick.value ; "grunt html" ! }
epub := { tutQuick.value ; "grunt epub" ! }

