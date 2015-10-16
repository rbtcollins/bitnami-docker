<?php

include ("db-config.php");

function db_connect_and_select_database($host, $user, $password) {
  $link = mysqli_connect($host, $user, $password);
  if (!$link) {
    echo "<p><h1>Could not connect to database server</h1></p>";
    return NULL;
  }
  if (!mysqli_select_db($link, DB_NAME)) {
    echo "<p><h1>Could not select database.</h1></p>";
    mysqli_close($link);
    return NULL;
  }
  return $link;
}

function increment_hits_count($link) {
  // create hits table if it does not exist
  if (!mysqli_query($link, 'SELECT 1 FROM hits LIMIT 1')) {
    if (mysqli_query($link, 'CREATE TABLE hits (cnt INT(11) NOT NULL)')) {
      mysqli_query($link, 'INSERT INTO hits(cnt) VALUES (0)');
    }
  }
  // increment hits count
  mysqli_query($link, 'UPDATE hits SET cnt = cnt + 1');
}

function display_hits_count($link) {
  $row = mysqli_fetch_array(mysqli_query($link, "SELECT cnt FROM hits LIMIT 1"));
  if ( $row['cnt'] == 1 ) {
    echo "<p><h1>You are the first visitor.</h1></p>";
  } else {
    echo "<p><h1>This page has been viewed " . $row['cnt'] . " times.</h1></p>";
  }
}

echo "<html>";
echo "<body background='images/background.jpg' text='#fff'>";
$link = db_connect_and_select_database(DB_HOST, DB_USER, DB_PASSWORD);
if ($link) {
  increment_hits_count($link);
  display_hits_count($link);
  mysqli_close($link);
}
echo "</body>";
echo "</html>";
?>
