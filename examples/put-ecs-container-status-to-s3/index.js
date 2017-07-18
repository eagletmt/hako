const AWS = require('aws-sdk');

const BUCKET = 'ecs-task-notifications';

exports.handler = (event, context, callback) => {
  const s3 = new AWS.S3();
  // console.log(JSON.stringify(event, null, 2));
  const taskArn = event.detail.taskArn;
  if (event.detail.lastStatus === 'RUNNING' && event.detail.containers.every((container) => container.lastStatus === 'RUNNING')) {
    console.log(`${taskArn} started`);
    s3.putObject({
      Bucket: BUCKET,
      Key: `task_statuses/${taskArn}/started.json`,
      Body: JSON.stringify(event),
    }, (err, data) => {
      if (err) {
        console.log(err);
        callback(err);
      } else {
        callback(null, 'Started');
      }
    });
  } else if (event.detail.lastStatus === 'STOPPED') {
    console.log(`${taskArn} stopped`);
    s3.putObject({
      Bucket: BUCKET,
      Key: `task_statuses/${taskArn}/stopped.json`,
      Body: JSON.stringify(event),
    }, (err, data) => {
      if (err) {
        console.log(err);
        callback(err);
      } else {
        callback(null, 'Stopped');
      }
    });
  } else {
    callback(null, 'Skipped');
  }
};
