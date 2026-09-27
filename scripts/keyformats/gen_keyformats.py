#!/usr/bin/env python3
"""Generate Sources/KeyFormats.swift from gitleaks-bare-rules.json (gitleaks, MIT; bare-token rules only,
sourcegraph rule trimmed of its bare 40-hex branch) plus curated-rules.json (trufflehog, secrets-patterns-db, vendor docs).
Usage: python3 scripts/keyformats/gen_keyformats.py
Every pattern is anchored to the whole (trimmed) value. Data only; matching lives in KeyRecognizer.swift."""
import json, re, sys
import os
HERE=os.path.dirname(os.path.abspath(__file__))
OUT=sys.argv[1] if len(sys.argv)>1 else os.path.join(HERE,'..','..','Sources','KeyFormats.swift')
bare=json.load(open(os.path.join(HERE,'gitleaks-bare-rules.json')))
extra=json.load(open(os.path.join(HERE,'curated-rules.json')))
DROP={'curl-auth-header','curl-auth-user','kubernetes-secret-yaml','nuget-config-password','sidekiq-sensitive-url',
      'microsoft-teams-webhook','slack-webhook-url','gitlab-session-cookie','jwt-base64','facebook-access-token','azure-ad-client-secret'}
GENERIC={'jwt':'JSON Web Token','private-key':'PEM private key'}
FAMILY_ALIASES={'gcp':['google','gcp','gemini','firebase'],'aws':['aws','amazon','bedrock'],'github':['github'],
 'gitlab':['gitlab'],'openai':['openai','chatgpt'],'anthropic':['anthropic','claude'],'slack':['slack'],'stripe':['stripe'],
 'huggingface':['huggingface'],'digitalocean':['digitalocean'],'sendgrid':['sendgrid','twilio-sendgrid'],'twilio':['twilio'],
 'notion':['notion'],'linear':['linear'],'npm':['npm'],'pypi':['pypi'],'perplexity':['perplexity','pplx'],'sentry':['sentry'],
 'shopify':['shopify'],'grafana':['grafana'],'databricks':['databricks'],'heroku':['heroku'],'planetscale':['planetscale'],
 'postman':['postman'],'pulumi':['pulumi'],'vault':['vault','hashicorp'],'hashicorp':['terraform','hashicorp'],'square':['square'],
 'adobe':['adobe'],'1password':['1password'],'airtable':['airtable'],'alibaba':['alibaba','aliyun'],'artifactory':['artifactory','jfrog'],
 'cloudflare':['cloudflare'],'doppler':['doppler'],'dynatrace':['dynatrace'],'flyio':['fly','flyio'],'octopus':['octopus'],'shippo':['shippo'],
 'rubygems':['rubygems'],'readme':['readme'],'prefect':['prefect'],'sourcegraph':['sourcegraph'],'settlemint':['settlemint'],
 'sendinblue':['sendinblue','brevo'],'scalingo':['scalingo'],'openshift':['openshift'],'maxmind':['maxmind'],'infracost':['infracost'],
 'harness':['harness'],'frameio':['frameio','frame.io'],'flutterwave':['flutterwave'],'easypost':['easypost'],'duffel':['duffel'],
 'clojars':['clojars'],'clickhouse':['clickhouse'],'authress':['authress'],'age':['age-encryption'],'intra42':['intra42'],
 'vercel':['vercel'],'supabase':['supabase'],'groq':['groq'],'xai':['xai','grok'],'mistral':['mistral'],'facebook':['facebook','meta']}
def family(rid):
    return rid.split('-')[0]
BRAND={'openai':'OpenAI','github':'GitHub','gitlab':'GitLab','xai':'xAI','pypi':'PyPI','npm':'npm','huggingface':'Hugging Face',
 'digitalocean':'DigitalOcean','sendgrid':'SendGrid','sendinblue':'Brevo','planetscale':'PlanetScale','hashicorp':'HashiCorp','gcp':'Google',
 'aws':'AWS','1password':'1Password','clickhouse':'ClickHouse','easypost':'EasyPost','frameio':'Frame.io','flyio':'Fly.io','intra42':'42 Intra',
 'maxmind':'MaxMind','readme':'ReadMe','rubygems':'RubyGems','settlemint':'SettleMint','sourcegraph':'Sourcegraph','vault':'HashiCorp Vault',
 'octopus':'Octopus Deploy','openshift':'OpenShift','langsmith':'LangSmith','langfuse':'Langfuse','posthog':'PostHog','newrelic':'New Relic',
 'nvidia':'NVIDIA','pubnub':'PubNub','trufflehog':'TruffleHog','zoho':'Zoho','stripe':'Stripe','slack':'Slack','twilio':'Twilio','notion':'Notion',
 'linear':'Linear','perplexity':'Perplexity','anthropic':'Anthropic','groq':'Groq','vercel':'Vercel','supabase':'Supabase','shopify':'Shopify',
 'databricks':'Databricks','sentry':'Sentry','postman':'Postman','pulumi':'Pulumi','grafana':'Grafana','heroku':'Heroku','doppler':'Doppler',
 'dynatrace':'Dynatrace','duffel':'Duffel','clojars':'Clojars','airtable':'Airtable','alibaba':'Alibaba Cloud','artifactory':'JFrog Artifactory',
 'adobe':'Adobe','age':'age','authress':'Authress','cloudflare':'Cloudflare','facebook':'Facebook','flutterwave':'Flutterwave','harness':'Harness',
 'infracost':'Infracost','jwt':'JSON Web Token','private':'PEM private key','scalingo':'Scalingo','shippo':'Shippo','square':'Square','prefect':'Prefect',
 'mailgun':'Mailgun','razorpay':'Razorpay','rootly':'Rootly','smooch':'Smooch','tailscale':'Tailscale','ubidots':'Ubidots','salesforce':'Salesforce',
 'salad':'Salad Cloud','robinhood':'Robinhood','ramp':'Ramp','portainer':'Portainer','plaid':'Plaid','pinecone':'Pinecone','pagarme':'Pagar.me',
 'lark':'Lark','fleetbase':'Fleetbase','flexport':'Flexport','endorlabs':'Endor Labs','contentful':'Contentful','apify':'Apify','apideck':'Apideck'}
WORD={'api':'API','pat':'PAT','jwt':'JWT','ssh':'SSH','oauth':'OAuth','id':'ID','json':'JSON','url':'URL','ca':'CA','scim':'SCIM','pw':'password','rrt':'RRT','ptt':'PTT','cicd':'CI/CD','tf':'Terraform','v2':'v2'}
def display(rid, desc):
    words=rid.replace('-',' ').split()
    fam=words[0]; rest=[WORD.get(w, w) for w in words[1:]]
    if rid in GENERIC: return GENERIC[rid]
    brand=BRAND.get(fam, fam.capitalize())
    return (brand+' '+' '.join(rest)).strip()
def anchor(rx):
    rx=rx.replace(r'(?:[\x60\'"\s;]|\\[nr]|$)','').replace(r'(?:[^\w-]|\z)','').replace(r'(?:$|[\\\'"\x60\s<),])','')
    rx=re.sub(r'^\(\?:\^\|\[[^\]]*\]\)','',rx)
    rx=rx.replace('\\b','')  # anchors replace word boundaries
    rx=rx.replace('(?P<','(?<')  # ICU named groups
    return '^(?:'+rx+')$'
rows=[]
for r in bare:
    if r['id'] in DROP: continue
    rows.append({'id':r['id'],'provider':display(r['id'],r['description']),'family':family(r['id']),
                 'generic':r['id'] in GENERIC,'pattern':anchor(r['regex']),'source':'gitleaks'})
for r in extra: rows.append(r)
seen=set(); rows=[x for x in rows if not (x['id'] in seen or seen.add(x['id']))]
rows.sort(key=lambda x:(x['family'],x['id']))
fams=sorted({x['family'] for x in rows})
def swift_str(s): return '"'+s.replace('\\','\\\\').replace('"','\\"')+'"'
lines=['// Generated by gen_keyformats.py from the gitleaks rule set (MIT) and curated additions.',
       '// Do not edit by hand; regenerate. Data only: matching lives in KeyRecognizer.swift.',
       '',
       'enum KeyFormats {',
       '    static let formats: [KeyFormat] = [']
for x in rows:
    lines.append(f"        KeyFormat(id: {swift_str(x['id'])}, provider: {swift_str(x['provider'])}, family: {swift_str(x['family'])}, isGeneric: {'true' if x['generic'] else 'false'}, pattern: {swift_str(x['pattern'])}),")
lines+=['    ]','','    /// Brand names by family, for the mismatch sentence.','    static let familyDisplayNames: [String: String] = [']
for f in fams:
    lines.append(f"        {swift_str(f)}: {swift_str(BRAND.get(f, f.capitalize()))},")
lines+=['    ]','','    /// Words that name a provider family when they appear in a destination service/account string.',
        '    static let familyAliases: [String: [String]] = [']
for f in fams:
    al=sorted(set(FAMILY_ALIASES.get(f,[f])))
    lines.append(f"        {swift_str(f)}: [{', '.join(swift_str(a) for a in al)}],")
lines+=['    ]','}','']
open(OUT,'w').write('\n'.join(lines))
print('formats:',len(rows),'families:',len(fams)); print('sources:',{s:sum(1 for x in rows if x['source']==s) for s in {x['source'] for x in rows}})
