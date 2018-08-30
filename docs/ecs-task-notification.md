# ECS task notification
In ECS scheduler, `hako oneshot` supports multiple methods of detecting task finish.

## ecs:DescribeTasks (default)
Use [DescribeTasks](http://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_DescribeTasks.html) API to get the task status.
This method can be used without any preparation or configuration, but the DescribeTasks API can return "Rate exceeded" error when there's several running `hako oneshot` processes.

## s3:GetObject
Amazon ECS has integration with Amazon CloudWatch Events. The integration notifies ECS task state changes to AWS Lambda, Amazon SNS, Amazon SQS, and so on.
http://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_cwe_events.html#ecs_task_events

Amazon S3 is a good storage for polling, so connecting CloudWatch Events to AWS Lambda and put the payload to S3 is more scalable than ecs:DescribeTasks.

The example implementation of AWS Lambda can be found in [../examples/put-ecs-container-status-to-s3](../examples/put-ecs-container-status-to-s3) directory.

To enable task notification with S3, you have to configure scheduler in definition file.

```js
{
  scheduler: {
    type: 'ecs',
    oneshot_notification_prefix: 's3://ecs-task-notifications/task_statuses?region=ap-northeast-1',
  },
}
```

It uses ecs-task-notifications bucket in ap-northeast-1 region.
