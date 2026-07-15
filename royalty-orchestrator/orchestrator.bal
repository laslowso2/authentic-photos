import ballerina/http;
import ballerina/os;
import ballerinax/rabbitmq;

function envOr(string key, string dflt) returns string {
    string v = os:getEnv(key);
    return v.trim().length() > 0 ? v : dflt;
}

final int servicePort = check int:fromString(envOr("PORT", "8080"));
final string dataServiceUrl = envOr("DATASERVICE_URL", "http://fin-dataservice:8080");
final decimal royaltyRate = check decimal:fromString(envOr("ROYALTY_RATE", "0.30"));
final string payoutQueue = envOr("PAYOUT_QUEUE", "royalty.payouts");

final http:Client dataService = check new (dataServiceUrl);
final rabbitmq:Client mq = check new (
    envOr("MQ_HOST", "rabbitmq.authentic-photos-mq-dev.svc.cluster.local"),
    check int:fromString(envOr("MQ_PORT", "5672")),
    auth = {username: envOr("MQ_USER", "authphotos_mq"), password: envOr("MQ_PASS", "")}
);

type PhotographerRevenue record {
    string photographer;
    decimal revenue;
    int sales;
};
type ReportEnvelope record {
    string report;
    PhotographerRevenue[] data;
};
type Payout record {
    string photographer;
    string period;
    decimal revenue;
    decimal royalty;
    decimal rate;
};

service /orchestrator on new http:Listener(servicePort) {

    function init() returns error? {
        check mq->queueDeclare(payoutQueue);
    }

    resource function get health() returns json {
        return {status: "ok", 'service: "royalty-orchestrator"};
    }

    // Run the royalty payout cycle for a period (optional year+month; else all-time):
    //  pull per-photographer revenue -> compute royalty -> publish a payout event per photographer.
    resource function post run(int? year, int? month) returns json|error {
        string period = (year is int && month is int)
            ? string `${year}-${month < 10 ? "0" : ""}${month}` : "all";
        string path = (year is int && month is int)
            ? string `/reports/revenueByPhotographer?year=${year}&month=${month}`
            : "/reports/revenueByPhotographer";

        ReportEnvelope report = check dataService->get(path);

        Payout[] payouts = [];
        foreach PhotographerRevenue r in report.data {
            decimal royalty = (r.revenue * royaltyRate).round(2);
            Payout p = {
                photographer: r.photographer, period: period,
                revenue: r.revenue, royalty: royalty, rate: royaltyRate
            };
            check mq->publishMessage({content: p, routingKey: payoutQueue});
            payouts.push(p);
        }
        return {status: "published", period: period, count: payouts.length(), payouts: payouts.toJson()};
    }
}
