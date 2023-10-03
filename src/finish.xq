xquery version "3.1";

declare namespace sm="http://exist-db.org/xquery/securitymanager";

(: the target collection into which the app is deployed :)
declare variable $target external;

declare variable $configuration-collection := $target || "/data/";
declare variable $backup-collection := "/db/tuttle-backup/"; 
declare variable $configuration-filename := "tuttle.xml";

(: look for backed up tuttle configuration :)
if (doc-available($backup-collection || $configuration-filename))
then ((: move/copy to collection :)
    util:log("info", "Restoring tuttle configuration from backup."),
    xmldb:move($backup-collection, $configuration-collection, $configuration-filename),
    xmldb:remove($backup-collection)
)
else ((: copy example configuration when no backup was found :)
    util:log("info", "No previous tuttle configuration found."),
    xmldb:copy-resource(
        $configuration-collection, "tuttle-example-config.xml",
        $configuration-collection, $configuration-filename
    )
)
,
(: tighten security for configuration file :)
sm:chmod(xs:anyURI($configuration-collection || $configuration-filename), "rw-r-----")
,
(: set gid for API :)
sm:chmod(xs:anyURI($target || "/modules/api.xql"), "rwxr-sr-x")

