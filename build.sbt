lazy val root = project.in(file("."))
  .settings(tutSettings)

tutSourceDirectory := sourceDirectory.value / "raw"

tutTargetDirectory := sourceDirectory.value / "pages"

scalaVersion := "2.11.7"

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
  "com.typesafe.slick" %% "slick"           % "3.1.1",
  "com.h2database"      % "h2"              % "1.4.185",
  "ch.qos.logback"      % "logback-classic" % "1.1.2"
)

lazy val pdf = taskKey[Unit]("Builds the PDF version of the book")

pdf := {
  val a = tut.value
  "grunt pdf" !
}
