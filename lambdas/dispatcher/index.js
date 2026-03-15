"use strict";

/**
 * Lambda 2 – Dispatcher
 *
 * Triggered by POST /dispatch.
 * Calls ECS RunTask to launch a Fargate task that publishes
 * the required JSON payload to the SNS verification topic.
 */

const {
  ECSClient,
  RunTaskCommand,
} = require("@aws-sdk/client-ecs");

const region = process.env.AWS_EXECUTING_REGION || process.env.AWS_REGION;
const ecs = new ECSClient({ region });

exports.handler = async (event) => {
  console.log("Dispatcher invoked", { region, event: JSON.stringify(event) });

  const subnetIds      = (process.env.SUBNET_IDS || "").split(",").filter(Boolean);
  const securityGroups = [process.env.SECURITY_GROUP_ID].filter(Boolean);

  const params = {
    cluster:        process.env.ECS_CLUSTER_ARN,
    taskDefinition: process.env.TASK_DEFINITION_ARN,
    // Use FARGATE_SPOT when available (cost-optimised).
    // Note: launchType and capacityProviderStrategy are mutually exclusive.
    capacityProviderStrategy: [
      { capacityProvider: "FARGATE_SPOT", weight: 1, base: 0 },
    ],
    networkConfiguration: {
      awsvpcConfiguration: {
        subnets:        subnetIds,
        securityGroups: securityGroups,
        // Public subnet → no NAT Gateway needed
        assignPublicIp: "ENABLED",
      },
    },
  };

  let taskArn;
  try {
    const response = await ecs.send(new RunTaskCommand(params));
    taskArn = response.tasks?.[0]?.taskArn || "unknown";
    console.log("ECS task started", { taskArn, region });
  } catch (err) {
    console.error("ECS RunTask failed", err);
    return {
      statusCode: 500,
      headers:    { "Content-Type": "application/json" },
      body: JSON.stringify({ error: err.message, region }),
    };
  }

  return {
    statusCode: 200,
    headers:    { "Content-Type": "application/json" },
    body: JSON.stringify({
      message:   "ECS task dispatched successfully",
      region:    region,
      taskArn:   taskArn,
      timestamp: new Date().toISOString(),
    }),
  };
};