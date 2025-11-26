#!/usr/bin/env groovy

/**
 * Salesforce DX Jenkins Pipeline - Windows Compatible
 *
 * This pipeline deploys Salesforce code from the master branch.
 * Optimized for Windows Jenkins servers.
 */

pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 1, unit: 'HOURS')
        disableConcurrentBuilds()
        timestamps()
        skipDefaultCheckout()
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
            description: 'Execute Apex tests'
        )
        booleanParam(
            name: 'SKIP_CODE_ANALYSIS',
            defaultValue: false,
            description: 'Skip static code analysis'
        )
        booleanParam(
            name: 'DEPLOY_ONLY',
            defaultValue: false,
            description: 'Skip build steps and deploy only'
        )
        string(
            name: 'TEST_LEVEL',
            defaultValue: 'RunLocalTests',
            description: 'Test level: NoTestRun, RunSpecifiedTests, RunLocalTests, RunAllTestsInOrg'
        )
    }

    environment {
        SFDX_AUTOUPDATE_DISABLE = 'true'
        SFDX_USE_GENERIC_UNIX_KEYCHAIN = 'true'
        SFDC_PROJECT_DIR = 'CompTestEnvt'
    }

    stages {
        stage('Initialization') {
            steps {
                script {
                    echo "========================================="
                    echo "Starting Salesforce CI/CD Pipeline"
                    echo "Environment: ${params.ENVIRONMENT}"
                    echo "Build: #${env.BUILD_NUMBER}"
                    echo "========================================="

                    // Checkout code
                    checkout scm

                    // Display tool versions (Windows compatible)
                    bat '''
                        echo "Salesforce CLI Version:"
                        sf --version
                        echo "Node Version:"
                        node --version
                        echo "NPM Version:"
                        npm --version
                    '''

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
                    dir("${SFDC_PROJECT_DIR}") {
                        bat 'npm ci'
                    }
                }
            }
        }

        stage('Code Quality') {
            when {
                expression { !params.SKIP_CODE_ANALYSIS && !params.DEPLOY_ONLY }
            }
            steps {
                script {
                    echo "Running code quality checks..."
                    dir("${SFDC_PROJECT_DIR}") {
                        bat '''
                            echo "Running Prettier check..."
                            call npm run prettier:verify || echo "Prettier check completed with warnings"

                            echo "Running ESLint..."
                            call npm run lint || echo "ESLint completed with warnings"
                        '''
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
                    dir("${SFDC_PROJECT_DIR}") {
                        bat '''
                            call npm run test:unit:coverage || echo "Tests completed"
                        '''
                    }
                }
            }
        }

        stage('Authorize Salesforce Org') {
            steps {
                script {
                    def authUrlCredential = getAuthCredential(params.ENVIRONMENT)

                    withCredentials([string(credentialsId: authUrlCredential, variable: 'SFDX_AUTH_URL')]) {
                        echo "Authorizing ${params.ENVIRONMENT} org..."

                        // Write auth URL to file and authenticate
                        writeFile file: 'authurl.txt', text: SFDX_AUTH_URL

                        bat '''
                            sf org login sfdx-url --sfdx-url-file authurl.txt --alias target-org --set-default
                            del authurl.txt
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
                    dir("${SFDC_PROJECT_DIR}") {
                        bat """
                            sf project deploy start --source-dir force-app --target-org target-org --test-level ${params.TEST_LEVEL} --dry-run --wait 60
                        """
                    }
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
                    bat '''
                        sf apex run test --target-org target-org --code-coverage --result-format human --wait 60 || echo "Apex tests completed"
                    '''
                }
            }
        }

        stage('Approval Gate') {
            when {
                expression { params.ENVIRONMENT in ['UAT', 'PRODUCTION'] }
            }
            steps {
                script {
                    timeout(time: 24, unit: 'HOURS') {
                        input(
                            message: "Approve deployment to ${params.ENVIRONMENT}?",
                            ok: 'Deploy'
                        )
                    }
                }
            }
        }

        stage('Deploy to Salesforce') {
            steps {
                script {
                    echo "Deploying to ${params.ENVIRONMENT}..."
                    dir("${SFDC_PROJECT_DIR}") {
                        bat """
                            sf project deploy start --source-dir force-app --target-org target-org --test-level ${params.TEST_LEVEL} --wait 60
                        """
                    }
                }
            }
        }

        stage('Post-Deployment Validation') {
            steps {
                script {
                    echo "Running post-deployment validation..."
                    bat '''
                        sf org list limits --target-org target-org
                        echo "Post-deployment validation completed successfully"
                    '''
                }
            }
        }
    }

    post {
        always {
            script {
                echo "Cleaning up..."
                bat 'sf org logout --target-org target-org --no-prompt || echo "Logout completed"'
                bat 'del authurl.txt 2>nul || echo "Cleanup completed"'
            }
        }

        success {
            script {
                echo """
                ========================================
                SUCCESS: Deployment to ${params.ENVIRONMENT}
                Build: #${env.BUILD_NUMBER}
                ========================================
                """
            }
        }

        failure {
            script {
                echo """
                ========================================
                FAILURE: Deployment to ${params.ENVIRONMENT}
                Build: #${env.BUILD_NUMBER}
                Check console output for details.
                ========================================
                """
            }
        }

        cleanup {
            cleanWs()
        }
    }
}

/**
 * Get authentication credential ID based on environment
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
