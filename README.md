<pre># update-synology-index
Synology synoindexd service only works with FTP, SMB, AFP
this program index all files that synoindexd left
you can select extensions, modified time, user and paths
for the searching and treatment

Usage: update-synoindex.sh  --> first for create config file
       change values of config/update-synoindex-conf.txt
       update-synoindex.sh

Example of config file:
for only mkv in the last hour for the user transmission with log directory /volume1/video/movies/ in the path /volume1/video/movies recursive


#extensions
MKV
#Modified time --> none or "command find time" --> 24 hours example = "-mtime 0" ----> 1 hour = "-mmin -60"
-mmin -60
#user: none, root, transmission, ftp, etc.
transmission
#directory for log/filename --> none, or path, or path/filename. for paths only must end with /
/volume1/video/movies/
#directories to treat --> 0 recursive, 1 no recursive
0 /volume1/video/movies
</pre>
