import { GetObjectCommand } from '@aws-sdk/client-s3';
import { s3_configured } from './service_config';

// generic aws helper

let f;

let defaults = {region: 'us-east-1'};
let cognito;

let credentials;
let s3;

// Hand over the AWS SDK classes the caller imported. Registering them is all
// this does — the token is not fetched until something actually asks S3 for
// something.
//
// It used to POST /token here, at import time, so every page that pulled this
// module in asked the server for Cognito credentials whether or not it went on
// to use them. On an instance with no Cognito configured that is a failing
// request and a console error on every load, for a capability the page was never
// going to exercise. Deferring costs nothing: the first caller pays the same
// round trip it would have waited on anyway, and the result is cached exactly as
// before. cloudrecorder's aws.js has always worked this way.
function refreshToken(x){
    f = x;
    // A later call re-registers and drops any cached client, which is what the
    // name suggests and what an expired-credentials retry wants.
    s3 = null;
};

function client(){
  if(s3) return s3;
  // Every S3 call in the app funnels through here, so this is the one place
  // worth guarding. Without Cognito and a region /token cannot answer, and the
  // old behaviour was to ask anyway, log the failure, and resolve to undefined —
  // so each caller then threw "cannot read properties of undefined" with nothing
  // naming the cause. Reject with something a caller can show instead.
  if(!s3_configured()){
    return Promise.reject(new Error('S3 is not configured on this server'));
  }
  s3 = fetch("/token", { method: "POST" })
  .then(res => res.json())
  .then( r => {
    const { tok, region } = r;
    let token = {...tok};
    defaults = { region };
    if(!cognito) cognito = new f.CognitoIdentityClient({...defaults});
    token.client = cognito;
    credentials = f.fromCognitoIdentity(token);
    return new f.S3Client({credentials, ...defaults});
  })
  .catch( e => { console.error("Error while getting token", e); });
  return s3;
}

const getTranscribeClient = () => {
    let c = {...defaults}
    c.credentials = credentials;
    return new f.TranscribeClient(c);
};

function getSignedUrlPromise(Bucket, Key){
  const params = { Bucket, Key };
  let cmd = new f.GetObjectCommand(params);
  return client().then( (s3) => f.getSignedUrl(s3, cmd, { expiresIn: 3600 }) );
}

const listObjectsV2 = (Bucket) => {
   const params = {Bucket, Delimiter: "/"};
   return listObjectsV2params(params);
}

const listObjectsV2params = (params) => {
   // const params = {Bucket, Delimiter: "/", Prefix: 'demo/' };
   const cmd  = new f.ListObjectsV2Command(params);
   return client().then( (s3) => s3.send(cmd) );
}

const headObject = (Bucket, Key) => {
   const params = {Bucket, Key};
   const cmd  = new f.HeadObjectCommand(params);
   return client().then( (s3) => s3.send(cmd) );
}

const putObject = (Bucket, Key, Body, ContentType) => {
  const params = {Bucket, Key, Body, ContentType};
  const cmd  = new f.PutObjectCommand(params);
  return client().then( (s3) => s3.send(cmd) );
}

const getObject = (Bucket, Key) => {
  const params = {Bucket, Key};
  const cmd  = new f.GetObjectCommand(params);
  return client().then( (s3) => s3.send(cmd) );
}

function s3url(url){
  const o = {};
  const found = url.match(/^s3:\/\/([^\/]+)\/(.+)/);
  if(found){
    o.bucket = found[1];
    o.key = found[2];
  }
  return o;
}

function S3url(url){
  const o = s3url(url);
  return { Bucket: o.bucket, Key: o.key };
}

function get_json_object(Bucket, Key, gets3){
  let p;
  if(gets3) p = gets3().then((s3) => s3.send(new GetObjectCommand({ Bucket, Key })));
  else      p = getObject(Bucket, Key);
  return p
  .then((x) => x.Body)
  .then((x) => x.transformToString())
  .then(JSON.parse)
}

function uploadObject(Bucket, Key, Body){
  return client().then((s3) => {
    const upload = new f.Upload({
      client: s3,
      params: {
        Bucket,
        Key,
        Body,
      },
    });
    return upload.done();
  });
}

function gets3(){
  return client();
}

export {
  getSignedUrlPromise,
  getTranscribeClient,
  listObjectsV2,
  listObjectsV2params,
  headObject,
  putObject,
  uploadObject,
  getObject,
  refreshToken,
  s3url,
  S3url,
  get_json_object,
  gets3
}
