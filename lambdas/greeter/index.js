"use strict";

/**
 * Lambda 1 – Greeter
 *
 * • Writes a record to the regional DynamoDB table (GreetingLogs).
 * • Publishes a JSON payload to the Unleash SNS verification topic.
 * • Returns 200 OK with the executing region.
 */

const {
  DynamoDBClient,
  PutItemCommand,
} = require("@aws-sdk/client-dynamodb");

const {
  SNSClient,
  PublishCommand,
} = require("@aws-sdk/client-sns");

const { randomUUID } = require("crypto");

// Clients are initialised outside the handler for connection reuse
const region = process.env.AWS_EXECUTING_REGION || process.env.AWS_REGION;
const ddb = new DynamoDBClient({ region });
// SNS topic lives in us-east-1 – publish cross-region
const sns = new SNSClient({ region: "us-east-1" });

exports.handler = async (event) => {
  console.log("Greeter invoked", { region, event: JSON.stringify(event) });

  const id = randomUUID();
  const timestamp = new Date().toISOString();
  const callerIp =
    event.requestContext?.http?.sourceIp || "unknown";

  // 1. Write to DynamoDB
  await ddb.send(
    new PutItemCommand({
      TableName: process.env.TABLE_NAME,
      Item: {
        id:        { S: id },
        timestamp: { S: timestamp },
        region:    { S: region },
        callerIp:  { S: callerIp },
      },
    })
  );
  console.log("DynamoDB record written", { id });

  // 2. Publish to SNS
  const snsPayload = {
    email:  process.env.CANDIDATE_EMAIL,
    source: "Lambda",
    region: region,
    repo:   process.env.GITHUB_REPO,
  };

  await sns.send(
    new PublishCommand({
      TopicArn: process.env.SNS_TOPIC_ARN,
      Message:  JSON.stringify(snsPayload),
      Subject:  "Candidate Verification – Lambda",
    })
  );
  console.log("SNS published", snsPayload);

  // 3. Return 200
  return {
    statusCode: 200,
    headers:    { "Content-Type": "application/json" },
    body: JSON.stringify({
      message:   "Hello from the Greeter!",
      region:    region,
      timestamp: timestamp,
      recordId:  id,
    }),
  };
};
