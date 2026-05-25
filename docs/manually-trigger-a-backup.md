# Manually trigger a backup

Sometimes, it's necessary to manually trigger backup actions.

This can be useful when other programs are used to consistently schedule tasks or to verify that environment variables are properly configured.

## Usage

Previously, performing an immediate backup required overwriting the entrypoint of the image. However, with the new setup, you can perform a backup directly with a parameterless command.

Run the image with the `backup` command and the required environment variables:

```shell
docker run --rm \
  --name actualbudget-backup \
  --mount type=volume,source=actualbudget-rclone-data,target=/config/ \
  -e ACTUAL_BUDGET_URL='https://actual.example.com' \
  -e ACTUAL_BUDGET_PASSWORD='' \
  -e ACTUAL_BUDGET_SYNC_ID='' \
  sangoisanga/actualbudget-backup:latest backup
```

You also need to mount the rclone config file and set the environment variables.

The only difference is that the environment variable `CRON` does not work because it does not start the CRON program, but exits the container after the backup is done.
