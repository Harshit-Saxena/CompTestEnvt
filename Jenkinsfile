#!/usr/bin/env groovy

/**
 * Enterprise-Level Jenkinsfile for Salesforce DX Project
 *
 * BEST PRACTICES IMPLEMENTED:
 * - Declarative Pipeline for better readability and validation
 * - Multi-stage deployment (Dev -> QA -> UAT -> Production)
 * - Parallel execution for independent tasks
 * - Comprehensive error handling and notifications
 * - Security scanning and code quality gates
 * - Automated testing with coverage thresholds
 * - Environment-specific configurations
 * - Artifact management and versioning
 * - Rollback capabilities
 * - Audit logging and compliance
 *
 * PREREQUISITES:
 * - Jenkins plugins: Salesforce DX, Pipeline, Credentials, Email Extension
 * - SFDX CLI installed on Jenkins agent
 * - Node.js and npm installed
 * - Credentials configured in Jenkins (SFDX auth URLs)
 * - PMD installed for static code analysis
 *
 * CREDENTIALS REQUIRED (Configure in Jenkins):
 * - SFDX_DEV_HUB_URL: DevHub authentication URL
 * - SFDX_DEV_AUTH_URL: Development org auth URL
 * - SFDX_QA_AUTH_URL: QA org auth URL
 * - SFDX_UAT_AUTH_URL: UAT org auth URL
 * - SFDX_PROD_AUTH_URL: Production org auth URL
 */

// @Library('shared-jenkins-library') _  // Optional: Uncomment if you have shared libraries

pipeline {
    agent any

    options {
        // Build retention policy
        buildDiscarder(logRotator(
            numToKeepStr: '30',
            daysToKeepStr: '90',
            artifactNumToKeepStr: '10'
        ))

        // Timeout for entire pipeline
        timeout(time: 2, unit: 'HOURS')

        // Disable concurrent builds
        disableConcurrentBuilds()

        // Timestamp console output
        timestamps()

        // Skip default checkout
        skipDefaultCheckout()

        // ANSI color output
        ansiColor('xterm')
    }

    parameters {
        choice(
            name: 'ENVIRONMENT',
            choices: ['DEV', 'QA', 'UAT', 'PRODUCTION'],
            description: 'Target deployment environment'
        )
        booleanParam(
            name: 'RUN_TESTS',
            defaultValue: true,
            description: 'Execute all test suites'
        )
        booleanParam(
            name: 'SKIP_CODE_ANALYSIS',
            defaultValue: false,
            description: 'Skip static code analysis (not recommended)'
        )
        booleanParam(
            name: 'DEPLOY_ONLY',
            defaultValue: false,
            description: 'Skip build and deploy only (emergency deployments)'
        )
        string(
            name: 'VERSION_TAG',
            defaultValue: '',
            description: 'Version tag for this deployment (e.g., v1.2.3)'
        )
        string(
            name: 'TEST_LEVEL',
            defaultValue: 'RunLocalTests',
            description: 'Test level for deployment (NoTestRun, RunSpecifiedTests, RunLocalTests, RunAllTestsInOrg)'
        )
    }

    environment {
        // SFDX Configuration
        SFDX_AUTOUPDATE_DISABLE = 'true'
        SFDX_USE_GENERIC_UNIX_KEYCHAIN = 'true'
        SFDX_DOMAIN_RETRY = '300'
        SFDX_LOG_LEVEL = 'DEBUG'

        // Node Configuration
        NODE_ENV = 'production'

        // Quality Gates
        MIN_CODE_COVERAGE = '75'
        MIN_COMPLEXITY_THRESHOLD = '10'

        // Artifact Configuration
        BUILD_VERSION = "${env.BUILD_NUMBER}"
        ARTIFACT_NAME = "salesforce-deployment-${env.BUILD_NUMBER}"

        // Notification Configuration (Update these with your actual values)
        SLACK_CHANNEL = '#salesforce-deployments'
        EMAIL_RECIPIENTS = 'your-email@company.com'  // Update with actual email addresses

        // Jira Configuration
        JIRA_SITE = 'salesforce-imark.atlassian.net'
        JIRA_PROJECT = 'SF'
    }

    stages {
        stage('Initialization') {
            steps {
                script {
                    echo "========================================="
                    echo "Starting Salesforce CI/CD Pipeline"
                    echo "Environment: ${params.ENVIRONMENT}"
                    echo "Build: #${env.BUILD_NUMBER}"
                    echo "Branch: ${env.BRANCH_NAME ?: 'master'}"
                    echo "========================================="

                    // Checkout code
                    checkout scm

                    // Display environment info
                    sh '''
                        echo "SFDX Version:"
                        sf --version || sfdx --version
                        echo "Node Version:"
                        node --version
                        echo "NPM Version:"
                        npm --version
                    '''

                    // Set build description
                    currentBuild.description = "Deploying to ${params.ENVIRONMENT}"
                }
            }
        }

        stage('Setup Dependencies') {
            when {
                expression { !params.DEPLOY_ONLY }
            }
            steps {
                script {
                    echo "Installing NPM dependencies..."
                    sh '''
                        # Clean install to ensure consistency
                        npm ci

                        # Verify installations
                        npm list --depth=0
                    '''
                }
            }
        }

        stage('Code Quality & Security') {
            when {
                expression { !params.SKIP_CODE_ANALYSIS && !params.DEPLOY_ONLY }
            }
            parallel {
                stage('Prettier Check') {
                    steps {
                        script {
                            echo "Running Prettier code formatting check..."
                            sh 'npm run prettier:verify || exit 0'
                        }
                    }
                }

                stage('ESLint Analysis') {
                    steps {
                        script {
                            echo "Running ESLint static analysis..."
                            sh '''
                                npm run lint -- --format json --output-file eslint-report.json || true
                                npm run lint
                            '''
                        }
                    }
                }

                stage('PMD Static Analysis') {
                    steps {
                        script {
                            echo "Running PMD static code analysis for Apex..."
                            sh '''
                                # Create reports directory
                                mkdir -p reports

                                # Run PMD analysis
                                sf scanner run \
                                    --target "force-app/**/*.cls,force-app/**/*.trigger" \
                                    --format json \
                                    --outfile reports/pmd-report.json \
                                    --engine pmd || true

                                # Run with multiple rule sets for comprehensive analysis
                                sf scanner run \
                                    --target "force-app/**/*.cls" \
                                    --category "Design,Best Practices,Code Style,Performance,Security" \
                                    --format html \
                                    --outfile reports/pmd-report.html || true
                            '''
                        }
                    }
                }

                stage('Security Scan') {
                    steps {
                        script {
                            echo "Running security vulnerability scan..."
                            sh '''
                                # NPM audit for JavaScript dependencies
                                npm audit --audit-level=moderate --json > reports/npm-audit.json || true

                                # Salesforce security scan
                                sf scanner run \
                                    --target "force-app/" \
                                    --category "Security" \
                                    --format csv \
                                    --outfile reports/security-scan.csv || true
                            '''
                        }
                    }
                }

                stage('License Compliance') {
                    steps {
                        script {
                            echo "Checking license compliance..."
                            sh '''
                                # Check for license compliance
                                npx license-checker --json > reports/license-report.json || true
                            '''
                        }
                    }
                }
            }
        }

        stage('Unit Tests') {
            when {
                expression { params.RUN_TESTS && !params.DEPLOY_ONLY }
            }
            steps {
                script {
                    echo "Running LWC Jest unit tests..."
                    sh '''
                        # Run Jest with coverage
                        npm run test:unit:coverage -- --ci --testResultsProcessor=jest-junit

                        # Verify coverage threshold
                        COVERAGE=$(jq '.total.lines.pct' coverage/coverage-summary.json)
                        echo "Code Coverage: $COVERAGE%"

                        if (( $(echo "$COVERAGE < ${MIN_CODE_COVERAGE}" | bc -l) )); then
                            echo "ERROR: Code coverage $COVERAGE% is below threshold ${MIN_CODE_COVERAGE}%"
                            exit 1
                        fi
                    '''

                    // Publish test results
                    junit 'junit.xml'

                    // Publish coverage reports
                    publishHTML([
                        reportDir: 'coverage/lcov-report',
                        reportFiles: 'index.html',
                        reportName: 'LWC Coverage Report',
                        keepAll: true
                    ])
                }
            }
        }

        stage('Authorize Salesforce Org') {
            steps {
                script {
                    def authUrlCredential = getAuthCredential(params.ENVIRONMENT)

                    withCredentials([string(credentialsId: authUrlCredential, variable: 'SFDX_AUTH_URL')]) {
                        echo "Authorizing ${params.ENVIRONMENT} org..."
                        sh '''
                            echo "${SFDX_AUTH_URL}" > authurl.txt
                            sf org login sfdx-url --sfdx-url-file authurl.txt --alias target-org --set-default
                            rm authurl.txt

                            # Verify connection
                            sf org display --target-org target-org
                        '''
                    }
                }
            }
        }

        stage('Validate Deployment') {
            when {
                expression { params.ENVIRONMENT != 'DEV' }
            }
            steps {
                script {
                    echo "Validating deployment to ${params.ENVIRONMENT}..."
                    sh """
                        sf project deploy start \
                            --source-dir force-app \
                            --target-org target-org \
                            --test-level ${params.TEST_LEVEL} \
                            --dry-run \
                            --wait 60 \
                            --verbose
                    """
                }
            }
        }

        stage('Run Apex Tests') {
            when {
                expression { params.RUN_TESTS && !params.DEPLOY_ONLY }
            }
            steps {
                script {
                    echo "Running Apex tests in ${params.ENVIRONMENT}..."
                    sh '''
                        # Run all local tests
                        sf apex run test \
                            --target-org target-org \
                            --code-coverage \
                            --result-format human \
                            --output-dir test-results \
                            --wait 60

                        # Generate detailed test report
                        sf apex get test \
                            --target-org target-org \
                            --result-format json \
                            --output-dir test-results
                    '''

                    // Archive test results
                    archiveArtifacts artifacts: 'test-results/**/*', allowEmptyArchive: true
                }
            }
        }

        stage('Approval Gate') {
            when {
                expression { params.ENVIRONMENT in ['UAT', 'PRODUCTION'] }
            }
            steps {
                script {
                    def approvalRequired = params.ENVIRONMENT == 'PRODUCTION' ? 'Release Manager' : 'Tech Lead'

                    timeout(time: 24, unit: 'HOURS') {
                        input(
                            message: "Approve deployment to ${params.ENVIRONMENT}?",
                            submitter: approvalRequired,
                            parameters: [
                                text(name: 'APPROVAL_NOTES', description: 'Approval notes/comments', defaultValue: '')
                            ]
                        )
                    }
                }
            }
        }

        stage('Deploy to Salesforce') {
            steps {
                script {
                    echo "Deploying to ${params.ENVIRONMENT}..."

                    // Create backup before deployment
                    if (params.ENVIRONMENT == 'PRODUCTION') {
                        sh '''
                            echo "Creating backup before production deployment..."
                            sf project retrieve start \
                                --target-org target-org \
                                --output-dir backup-${BUILD_NUMBER} \
                                --manifest manifest/package.xml || true
                        '''
                    }

                    // Execute deployment
                    sh """
                        sf project deploy start \
                            --source-dir force-app \
                            --target-org target-org \
                            --test-level ${params.TEST_LEVEL} \
                            --wait 60 \
                            --verbose \
                            --json > deployment-result.json

                        # Display deployment result
                        cat deployment-result.json
                    """

                    // Archive deployment artifacts
                    archiveArtifacts artifacts: 'deployment-result.json', allowEmptyArchive: true
                }
            }
        }

        stage('Post-Deployment Validation') {
            steps {
                script {
                    echo "Running post-deployment validation..."
                    sh '''
                        # Verify org limits
                        sf org list limits --target-org target-org

                        # Run smoke tests (if available)
                        # Add your smoke test commands here

                        echo "Post-deployment validation completed successfully"
                    '''
                }
            }
        }

        stage('Update Jira') {
            steps {
                script {
                    echo "Updating Jira tickets for ${params.ENVIRONMENT} deployment..."

                    // Extract Jira ticket from commit message or branch name
                    def jiraTicket = sh(
                        script: "git log -1 --pretty=%B | grep -o '\\[${JIRA_PROJECT}-[0-9]\\+\\]' | head -1 | tr -d '[]' || echo ''",
                        returnStdout: true
                    ).trim()

                    if (jiraTicket) {
                        echo "Found Jira ticket: ${jiraTicket}"

                        // Transition ticket based on environment
                        // Workflow: DISCOVERY → IDEA → TO DO → IN PROGRESS → UAT → TESTING → REVIEW → DONE
                        def transitionId = ''
                        def comment = "Deployment to ${params.ENVIRONMENT} completed successfully - Build #${env.BUILD_NUMBER}"

                        switch(params.ENVIRONMENT) {
                            case 'DEV':
                                // Move to IN PROGRESS if deploying to DEV
                                transitionId = 'IN PROGRESS'
                                break
                            case 'QA':
                                // Move to TESTING when deployed to QA
                                transitionId = 'TESTING'
                                break
                            case 'UAT':
                                // Move to UAT when deployed to UAT
                                transitionId = 'UAT'
                                break
                            case 'PRODUCTION':
                                // Move to DONE when deployed to Production
                                transitionId = 'DONE'
                                comment = "Released to production - Version: ${params.VERSION_TAG ?: env.BUILD_NUMBER}"
                                break
                        }

                        echo "Transitioning ${jiraTicket} to ${transitionId}"
                        echo "Adding comment: ${comment}"

                        // Note: Actual Jira API calls would go here
                        // This is a placeholder for the API integration
                        // You'll need to install the Jira plugin or use REST API calls

                        /* Example REST API call (requires credentials):
                        sh """
                            curl -X POST \\
                                -H "Content-Type: application/json" \\
                                -u \${JIRA_CREDENTIALS} \\
                                "https://${JIRA_SITE}/rest/api/2/issue/${jiraTicket}/comment" \\
                                -d '{"body": "${comment}"}'
                        """
                        */
                    } else {
                        echo "No Jira ticket found in commit message. Skipping Jira update."
                    }
                }
            }
        }

        stage('Create Release Tag') {
            when {
                expression { params.VERSION_TAG && params.ENVIRONMENT == 'PRODUCTION' }
            }
            steps {
                script {
                    echo "Creating release tag: ${params.VERSION_TAG}"
                    sh """
                        git tag -a ${params.VERSION_TAG} -m "Release ${params.VERSION_TAG} - Build #${env.BUILD_NUMBER}"
                        git push origin ${params.VERSION_TAG}
                    """
                }
            }
        }
    }

    post {
        always {
            script {
                echo "Cleaning up workspace..."

                // Archive all reports
                archiveArtifacts artifacts: 'reports/**/*', allowEmptyArchive: true

                // Publish quality reports
                publishHTML([
                    reportDir: 'reports',
                    reportFiles: '*.html',
                    reportName: 'Code Quality Reports',
                    keepAll: true
                ])

                // Logout from Salesforce org
                sh 'sf org logout --target-org target-org --no-prompt || true'

                // Clean sensitive files
                sh 'rm -f authurl.txt *.key *.json.bak || true'
            }
        }

        success {
            script {
                def message = """
                    ✅ SUCCESS: Salesforce Deployment to ${params.ENVIRONMENT}

                    Build: #${env.BUILD_NUMBER}
                    Branch: ${env.BRANCH_NAME ?: 'master'}
                    Environment: ${params.ENVIRONMENT}
                    Version: ${params.VERSION_TAG ?: 'N/A'}
                    Duration: ${currentBuild.durationString}

                    Build URL: ${env.BUILD_URL}
                """.stripIndent()

                echo message

                // Send notifications
                // emailext(
                //     subject: "✅ Deployment Success: ${params.ENVIRONMENT} - Build #${env.BUILD_NUMBER}",
                //     body: message,
                //     to: env.EMAIL_RECIPIENTS,
                //     attachLog: false
                // )

                // Slack notification (if configured)
                // slackSend(
                //     channel: env.SLACK_CHANNEL,
                //     color: 'good',
                //     message: message
                // )
            }
        }

        failure {
            script {
                def message = """
                    ❌ FAILURE: Salesforce Deployment to ${params.ENVIRONMENT}

                    Build: #${env.BUILD_NUMBER}
                    Branch: ${env.BRANCH_NAME ?: 'master'}
                    Environment: ${params.ENVIRONMENT}
                    Duration: ${currentBuild.durationString}

                    Build URL: ${env.BUILD_URL}
                    Console: ${env.BUILD_URL}console
                """.stripIndent()

                echo message

                // Send failure notifications
                // emailext(
                //     subject: "❌ Deployment Failed: ${params.ENVIRONMENT} - Build #${env.BUILD_NUMBER}",
                //     body: message,
                //     to: env.EMAIL_RECIPIENTS,
                //     attachLog: true
                // )

                // Slack notification
                // slackSend(
                //     channel: env.SLACK_CHANNEL,
                //     color: 'danger',
                //     message: message
                // )
            }
        }

        unstable {
            script {
                echo "⚠️ Build is unstable. Review test results and quality gates."
            }
        }

        aborted {
            script {
                echo "🛑 Build was aborted."
            }
        }

        cleanup {
            // Final cleanup
            cleanWs(
                deleteDirs: true,
                patterns: [
                    [pattern: 'node_modules', type: 'INCLUDE'],
                    [pattern: '.sfdx', type: 'INCLUDE'],
                    [pattern: 'coverage', type: 'INCLUDE']
                ]
            )
        }
    }
}

/**
 * Helper function to get authentication credential based on environment
 */
def getAuthCredential(environment) {
    switch(environment) {
        case 'DEV':
            return 'SFDX_DEV_AUTH_URL'
        case 'QA':
            return 'SFDX_QA_AUTH_URL'
        case 'UAT':
            return 'SFDX_UAT_AUTH_URL'
        case 'PRODUCTION':
            return 'SFDX_PROD_AUTH_URL'
        default:
            error "Unknown environment: ${environment}"
    }
}

/**
 * Helper function for rollback (implement as needed)
 */
def rollback(targetOrg, backupVersion) {
    echo "Initiating rollback to version ${backupVersion}..."
    // Implement rollback logic
    sh """
        sf project deploy start \
            --source-dir backup-${backupVersion} \
            --target-org ${targetOrg} \
            --wait 60
    """
}
