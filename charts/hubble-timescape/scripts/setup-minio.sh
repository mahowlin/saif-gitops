#!/bin/bash
until mc --insecure config host add minio $MINIO_HOST $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD
do
  echo 'Wait minio to startup...' && sleep 0.2
done
mc --insecure mb  --ignore-existing minio/timescape
# Remove exiting rules to make sure there are no left over rules
mc --insecure ilm rule rm --all --force  minio/timescape
mc --insecure ilm rule add --expire-days $RETENTION  minio/timescape
