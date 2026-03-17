# Hardening a Containerized Static Site (Flaude) with nginx

---

## Learning Objectives

By the end of this lab, students will be able to:

1. Serve a static site from a custom nginx Docker container
2. Incrementally apply and verify server-side configurations
3. Use `curl` and browser DevTools to observe and validate HTTP behavior
4. Explain the purpose and tradeoff of each configuration decision
5. Write a minimal but production-realistic `nginx.conf`

---

## Lab Setup

### Project Structure

```
CIS467-SP26-docker-flaude/
├── Dockerfile
├── README.md
├── nginx.conf
├── index.html
├── src/
│   ├── app.js      
│   └── style.css
```

### Base Dockerfile

Students start with this and do not modify it — all changes happen in `nginx.conf`:

```dockerfile
FROM nginx:alpine
COPY site/ /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
```

### Rebuild Helper

You can use this command throughout the lab to build and run your image:

```bash
docker build -t lab-nginx . && docker run --rm -p 8080:80 lab-nginx
```

---

## Checkpoint 0 — Baseline (Just Serve Files)

### Goal
Confirm the site loads before any custom configuration is applied.

### nginx.conf

```nginx
events {}

http {
    include /etc/nginx/mime.types;

    server {
        listen 80;
        root /usr/share/nginx/html;
        index index.html;
    }
}
```

### Verification

```bash
curl -I http://localhost:8080/
```

**Expected:** `200 OK`, no special headers, no compression.

### 0.1 - Reflection Question
> What headers does nginx send by default? Are any of them surprising? 

```HTTP/1.1 200 OK
Server: nginx/1.29.5
Date: Wed, 11 Mar 2026 18:30:01 GMT
Content-Type: text/html
Content-Length: 19820
Last-Modified: Mon, 09 Mar 2026 18:38:20 GMT
Connection: keep-alive
ETag: "69af139c-4d6c"
Accept-Ranges: bytes
```
These are the headers nginx sends by default. I asked ChatGPT about the Content-Length header becuase I thought it was the number of characters. It is actually the number of bytes. 

---

## Checkpoint 1 — Compression

### Goal
Reduce asset transfer size for text-based files using gzip.

### Changes to `nginx.conf`

Add inside the `http` block:

```nginx
gzip on;
gzip_types text/plain text/css application/javascript application/json;
gzip_min_length 1024;
```

### Verification

```bash
curl -I -H "Accept-Encoding: gzip" http://localhost:8080/index.js
```

Look for: `Content-Encoding: gzip`

```HTTP/1.1 200 OK
Server: nginx/1.29.5
Date: Mon, 16 Mar 2026 20:07:46 GMT
Content-Type: application/javascript
Last-Modified: Fri, 13 Mar 2026 18:07:23 GMT
Connection: keep-alive
ETag: W/"69b4525b-59a"
Content-Encoding: gzip
```

Also verify in browser DevTools → Network tab → select a JS or CSS file →
check the **Response Headers** panel.

### 1.1 Reflection Question
> Why does `gzip_min_length` exist? What's the cost of compressing a 200-byte file?
`gzip_min_length` ensures that a file is big enough to require being zipped. If a file is small enough then zipping is unecessary; becuase you won't be saving any processing power by compressing it.

---

## Checkpoint 2 — Cache Control 

### Goal
Apply appropriate caching strategies: aggressive caching for fingerprinted assets,
no caching for HTML entry points.

### Changes to `nginx.conf`

Add inside the `server` block:

```nginx
# HTML — always revalidate
location ~* \.html$ {
    add_header Cache-Control "no-cache, must-revalidate";
}

# Fingerprinted assets — cache for 1 year
location ~* \.(js|css|png|jpg|woff2|mp4)$ {
    add_header Cache-Control "public, max-age=31536000, immutable";
}
```

### Verification

```bash
curl -I http://localhost:8080/index.html
curl -I http://localhost:8080/My_Differential_Equation.mp4
```

Confirm different `Cache-Control` values on each response.

```HTTP/1.1 200 OK
Server: nginx/1.29.5
Date: Mon, 16 Mar 2026 20:12:38 GMT
Content-Type: text/html
Content-Length: 615
Last-Modified: Wed, 04 Feb 2026 20:18:43 GMT
Connection: keep-alive
ETag: "6983a9a3-267"
Cache-Control: no-cache, must-revalidate
Accept-Ranges: bytes
```

```HTTP/1.1 200 OK
Server: nginx/1.29.5
Date: Mon, 16 Mar 2026 20:16:03 GMT
Content-Type: video/mp4
Content-Length: 4767395
Last-Modified: Mon, 16 Mar 2026 20:14:15 GMT
Connection: keep-alive
ETag: "69b86497-48bea3"
Cache-Control: public, max-age=31536000, immutable
Accept-Ranges: bytes
```

### 2.1 - Reflection Question
> Why would caching `index.html` aggressively be dangerous for a single-page app?
> What would happen if a user's browser cached a stale `index.html` pointing to
> old JS bundles?

Aggressively caching `index.html` in this case could result in old content being displayed becuase the browser wouldn't be regularly checking the server. 
Caching a stale `index.html` might result in a broken site due to js bundles that could be nonexistent. 

---

## Checkpoint 3 — Security Headers

### Goal
Protect users from common browser-level attacks by adding standard security headers.

### Changes to `nginx.conf`

Add inside the `server` block (or a dedicated location):

```nginx
add_header X-Frame-Options "SAMEORIGIN";
add_header X-Content-Type-Options "nosniff";
add_header Referrer-Policy "strict-origin-when-cross-origin";
add_header Permissions-Policy "geolocation=(), camera=(), microphone=()";
add_header Content-Security-Policy
    "default-src 'self'; script-src 'self'; style-src 'self';";
```

### Verification

```bash
curl -I http://localhost:8080/
```

All five headers should appear in the response.

```HTTP/1.1 200 OK
Server: nginx/1.29.5
Date: Mon, 16 Mar 2026 20:23:07 GMT
Content-Type: text/html
Content-Length: 615
Last-Modified: Wed, 04 Feb 2026 20:18:43 GMT
Connection: keep-alive
ETag: "6983a9a3-267"
Cache-Control: no-cache, must-revalidate
Cache-Control: public, max-age=31536000, immutable
X-Frame-Options: SAMEORIGIN
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: geolocation=(), camera=(), microphone=()
Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self';
Accept-Ranges: bytes
```

Also check: https://securityheaders.com (enter `http://localhost:8080` if using
a tunneling tool, or deploy to a VPS for full scoring).

### 3.1 - Reflection Questions
> Break the CSP intentionally — add an inline `<script>` tag to `index.html`
> and observe the browser console error. What does this teach you about
> how CSP is enforced?

I got this error: "Applying inline style violates the following Content Security Policy directive 'style-src 'self''. Either the 'unsafe-inline' keyword, a hash ('sha256-4qxDpGEJUcxjIP3NOEWlTKBLTDQ5y6fmRuEEO6ZT9Q0='), or a nonce ('nonce-...') is required to enable inline execution. The action has been blocked." 
I had to research this a little bit, but CSP is enforced when the browser checks page resources against the CSP rules. If one does not meet the rules, the browser prevents the script from running.

---

## Checkpoint 4 — SPA Routing Fallback

### Goal
Ensure that client-side routes (e.g., `/dashboard`, `/profile/42`) return
`index.html` instead of a 404, allowing JavaScript frameworks to handle routing.

### Setup

Add a link in `index.html` to a route that has no corresponding HTML file:

```html
<a href="/dashboard">Go to Dashboard</a>
```

Without the fallback, clicking this returns a 404.

### Changes to `nginx.conf`

Replace or update the default `location` block:

```nginx
location / {
    try_files $uri $uri/ /index.html;
}
```

### Verification

```bash
curl -I http://localhost:8080/dashboard
```

**Expected:** `200 OK` with the content of `index.html` — not a 404.

Also add a custom 404 page to handle truly missing assets:

```nginx
error_page 404 /404.html;
```

### 4.1 - Reflection Questions
> If every route returns `index.html` with a 200, what are the SEO implications?
> How do SSR frameworks like Next.js solve this problem?

The lack of true 404 errors and the confusing return of 200 with pages that don't exist would hurt a page's SEO.
Server-Side Rendering allows the server to go ahead and render the page into HTML before sending it to the client. This cuts down on the time it takes to render the page, and shows that there is different content on the different pages, rather than just the single `index.html`. SSR frameworks will also return accurate responses for each page.  

---

## Checkpoint 5 — Rate Limiting

### Goal
Protect the server from abusive request patterns using nginx's built-in
rate limiting directives.

### Changes to `nginx.conf`

Add to the `http` block:

```nginx
limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
```

Apply it in the `server` block:

```nginx
limit_req zone=general burst=20 nodelay;
limit_req_status 429;
```

### Verification

Use a loop to fire rapid requests:

```bash
for i in $(seq 1 30); do curl -s -o /dev/null -w "%{http_code}\n" \
  http://localhost:8080/; done
```

Some responses should return `429 Too Many Requests` once the burst is exhausted.

### 5.1 - Reflection Question
> Rate limiting on a static site might seem overkill — when would it actually
> matter in production?

It would protect the site from hacker attacts and being overloaded with requests. It keeps the site accessibile and running smoothly for users. 

---

## Checkpoint 6 — Block Sensitive Paths

### Goal
Prevent accidental exposure of configuration files, version control artifacts,
or environment files that might exist in the container.

### Changes to `nginx.conf`

```nginx
location ~ /\. {
    deny all;
    return 404;
}

location ~* \.(env|git|yml|yaml|config)$ {
    deny all;
    return 404;
}
```

### Verification

```bash
# Create a test file to block
echo "SECRET=abc123" > site/.env

# Rebuild and test
curl -I http://localhost:8080/.env
```

**Expected:** `404` — not the file contents.

### 6.1 - Reflection Question
> Why return `404` instead of `403 Forbidden`? What information does each
> status code leak to an attacker? 

Sending a 403 (Forbidden) error tells hackers that the file does indeed exist, rather than a 404 (Not found) which conceals whether or not the file is there.

---

## Final nginx.conf

You should have a complete, working config. Review it as a whole and identify any ordering issues or redundancies.

---

## Deliverable: Written Reflection (Individual)

Submit a short written response (200-500 words) answering the following:

1. Which configuration had the most visible impact when you verified it? Why?
2. Choose one header or directive you added. Research what a real-world attack
   looks like that it mitigates, and describe it briefly.
3. What does this lab reveal about what managed hosting platforms like Netlify
   are silently doing on your behalf?

Configuring the rate limiting seemed to have the quickest and most obvious response. It was clear that as soon as the requests hit the rate limit, it returned a 429 “Too Many Requests” error. This security feature is meant to protect the server from overloading and to stop malicious attacks such as DDoS. 

I chose these two rules: 

```nginx
location ~ /\. {
   deny all;
   return 404;
}

location ~* \.(env|git|yml|yaml|config)$ {
   deny all;
   return 404;
}
``` 

These changes to nginx.conf provide protection if environment or configuration files or other sensitive pieces of data were included in the container in production. Were these files to be searched for by attackers the returned response would be a 404, which means Not Found, rather than a 403, which is Forbidden. This adds an extra layer of security in that the attackers are not alerted to the existence of the sensitive files. This discourages them from accessing the source code from GitHub, stealing API keys, or infiltrating the database. 
	
Cloud-hosting services like Netlify automatically provide all of the features that we manually added in this lab, such as adding security headers, enabling gzip, and configuring caching strategies, among other server-side security features. Netlify will also manage routing paths and handle responses for nonexistent routes, as well as provide a secure dashboard for secrets. 

---

## Grading Rubric

| Component | Points |
|---|---|
| All 6 checkpoints complete with working config | 40 |
| Verification commands run and output documented (screenshots or paste) | 20 |
| Written reflection — depth and specificity | 30 |
| Config is clean, commented, and well-organized | 10 |
| **Total** | **100** |
