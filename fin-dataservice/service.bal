import ballerina/http;
import ballerina/sql;
import ballerina/os;
import ballerinax/mysql;
import ballerinax/mysql.driver as _;

// --- config from environment (same pattern as the Node API; same image runs per-env) ---
function envOr(string key, string dflt) returns string {
    string v = os:getEnv(key);
    return v.trim().length() > 0 ? v : dflt;
}

final int servicePort = check int:fromString(envOr("PORT", "8080"));

final mysql:Client dw = check new (
    host = envOr("DB_HOST", "localhost"),
    port = check int:fromString(envOr("DB_PORT", "3306")),
    user = envOr("DB_USER", "authphotos_app"),
    password = envOr("DB_PASSWORD", ""),
    database = envOr("DB_NAME", "findw")
);

// Collect a query stream into a JSON report envelope.
function collect(stream<record {}, sql:Error?> rs, string name) returns json|error {
    json[] rows = [];
    check from record {} entry in rs
        do {
            rows.push(entry.toJson());
        };
    return {report: name, data: rows};
}

// WSO2-DataService-style REST API over the financial warehouse.
service /reports on new http:Listener(servicePort) {

    resource function get health() returns json {
        return {status: "ok", 'service: "fin-dataservice"};
    }

    // Overall totals.
    resource function get summary() returns json|error {
        record {} row = check dw->queryRow(`
            SELECT ROUND(SUM(amount_cents)/100, 2) AS total_revenue,
                   COUNT(*)                        AS total_sales,
                   COUNT(DISTINCT customer_ref)    AS customers,
                   ROUND(AVG(amount_cents)/100, 2) AS avg_order_value
            FROM fact_sales`);
        return {report: "summary", data: row.toJson()};
    }

    // Revenue trend by month.
    resource function get revenueByMonth() returns json|error {
        stream<record {}, sql:Error?> rs = dw->query(`
            SELECT d.year AS year, d.month AS month, d.month_name AS month_name,
                   ROUND(SUM(f.amount_cents)/100, 2) AS revenue, COUNT(*) AS sales
            FROM fact_sales f JOIN dim_date d ON d.date_key = f.date_key
            GROUP BY d.year, d.month, d.month_name
            ORDER BY d.year, d.month`);
        return collect(rs, "revenue_by_month");
    }

    // Best-selling photos by revenue.
    resource function get topPhotos() returns json|error {
        stream<record {}, sql:Error?> rs = dw->query(`
            SELECT p.photo_id AS photo_id, p.title AS title, p.photographer AS photographer,
                   ROUND(SUM(f.amount_cents)/100, 2) AS revenue, COUNT(*) AS sales
            FROM fact_sales f JOIN dim_photo p ON p.photo_id = f.photo_id
            GROUP BY p.photo_id, p.title, p.photographer
            ORDER BY revenue DESC
            LIMIT 5`);
        return collect(rs, "top_photos");
    }

    // Revenue per photographer (optionally for a given year+month) — feeds royalty payouts.
    resource function get revenueByPhotographer(int? year, int? month) returns json|error {
        sql:ParameterizedQuery q;
        if year is int && month is int {
            q = `SELECT p.photographer AS photographer,
                        ROUND(SUM(f.amount_cents)/100, 2) AS revenue, COUNT(*) AS sales
                 FROM fact_sales f
                 JOIN dim_photo p ON p.photo_id = f.photo_id
                 JOIN dim_date  d ON d.date_key = f.date_key
                 WHERE d.year = ${year} AND d.month = ${month}
                 GROUP BY p.photographer ORDER BY revenue DESC`;
        } else {
            q = `SELECT p.photographer AS photographer,
                        ROUND(SUM(f.amount_cents)/100, 2) AS revenue, COUNT(*) AS sales
                 FROM fact_sales f
                 JOIN dim_photo p ON p.photo_id = f.photo_id
                 GROUP BY p.photographer ORDER BY revenue DESC`;
        }
        stream<record {}, sql:Error?> rs = dw->query(q);
        return collect(rs, "revenue_by_photographer");
    }

    // Revenue split by license type.
    resource function get revenueByLicense() returns json|error {
        stream<record {}, sql:Error?> rs = dw->query(`
            SELECT f.license_type AS license_type,
                   ROUND(SUM(f.amount_cents)/100, 2) AS revenue, COUNT(*) AS sales
            FROM fact_sales f
            GROUP BY f.license_type
            ORDER BY revenue DESC`);
        return collect(rs, "revenue_by_license");
    }
}
