local utopia = import 'utopia/utopia/registry.libsonnet';
local service = utopia.registry.service;
local environment = utopia.registry.environment;
local argocd = utopia.registry.target.argo;

// Example service called make-it-rain, powering a dashboard of falling
// gold coins whenever anyone takes a payment via GoCardless.
//
// Banking teams love money, which is why they created this dashboard.
// It's officially owned by banking-integrations, but core-banking
// sometimes optimise the React code.
//
// It consumes data about new payments from Google Pub/Sub, and has a
// separate Google Cloud Platform project for each of its environments,
// of which there are two: staging and production.
service.new('make-it-rain', 'gocardless/make-it-rain') +
service.mixin.withTeam('banking-integrations') +
service.mixin.withGoogleServices([
  'pubsub.googleapis.com',
]) +
service.mixin.withEnvironments([
  environment.map(
    // By default, every environment should have banking-integrations as
    // admins, and core-banking as operators (they provide on-call cover
    // for the falling gold coins).
    environment.mixin.rbac.withAdmins('banking-integrations') +
    environment.mixin.rbac.withOperators('core-banking'),
    function(environment) [
      environment.new('staging') +
      environment.mixin.withGoogleProject('gc-prd-make-it-stag-833e') +
      environment.mixin.withTargets([
        argocd.new(cluster='compute-staging-brava', namespace='make-it-rain'),
      ]),
      // Unlike most services, the production environment should permit
      // a non-engineering team to open consoles. Sometimes we take a
      // manual payment outside of GoCardless, and banking-operations
      // open a make-it-rain console and run a script, so we don't miss
      // any gold coins.
      environment.new('production') +
      environment.mixin.rbac.withOperatorsMixin('banking-operations') +
      environment.mixin.withGoogleProject('gc-prd-make-it-prod-1eb1') +
      environment.mixin.withTargets([
        argocd.new(cluster='compute-banking', namespace='make-it-rain'),
      ]),
    ],
  ),
])
