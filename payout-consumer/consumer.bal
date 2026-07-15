import ballerina/os;
import ballerina/log;
import ballerinax/rabbitmq;
import ballerinax/mysql;
import ballerinax/mysql.driver as _;

function envOr(string key, string dflt) returns string {
    string v = os:getEnv(key);
    return v.trim().length() > 0 ? v : dflt;
}

final mysql:Client dw = check new (
    host = envOr("DB_HOST", "localhost"),
    port = check int:fromString(envOr("DB_PORT", "3306")),
    user = envOr("DB_USER", "authphotos_app"),
    password = envOr("DB_PASSWORD", ""),
    database = envOr("DB_NAME", "findw")
);

type Payout record {
    string photographer;
    string period;
    decimal revenue;
    decimal royalty;
    decimal rate;
};

listener rabbitmq:Listener mqListener = new (
    envOr("MQ_HOST", "rabbitmq.authentic-photos-mq-dev.svc.cluster.local"),
    check int:fromString(envOr("MQ_PORT", "5672")),
    auth = {username: envOr("MQ_USER", "authphotos_mq"), password: envOr("MQ_PASS", "")}
);

// Message processor: each payout event -> a row in findw.payouts (the async half; AAA's pattern).
@rabbitmq:ServiceConfig {
    queueName: "royalty.payouts"
}
service on mqListener {
    remote function onMessage(Payout payout) returns error? {
        int revenueCents = <int>(payout.revenue * 100);
        int royaltyCents = <int>(payout.royalty * 100);
        _ = check dw->execute(`
            INSERT INTO payouts (photographer, period, revenue_cents, royalty_cents, royalty_rate, status)
            VALUES (${payout.photographer}, ${payout.period}, ${revenueCents}, ${royaltyCents}, ${payout.rate}, 'paid')`);
        log:printInfo(string `payout recorded: ${payout.photographer} ${payout.period} royalty=${payout.royalty}`);
    }
}
