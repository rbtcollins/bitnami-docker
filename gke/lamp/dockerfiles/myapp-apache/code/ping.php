<?php

include ("db-config.php");

function db_connect_and_select_database($host, $user, $password) {
  $link = mysqli_connect($host, $user, $password);
  if (!$link) {
    return NULL;
  }
  if (!mysqli_select_db($link, DB_NAME)) {
    mysqli_close($link);
    return NULL;
  }
  return $link;
}

echo "<html>";
echo "<body>";
$link = db_connect_and_select_database(DB_HOST, DB_USER, DB_PASSWORD);
if ($link) {
  echo "PONG!";
  mysqli_close($link);
} else {
  die();
}
echo "</body>";
echo "</html>";
?>
