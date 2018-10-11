#!/bin/bash

#******************************************************************************
#    AWS VPC Creation Shell Script
#******************************************************************************
#
# SYNOPSIS
#    Automates the creation of a custom IPv4 VPC, having both TWO public and 
#    private subnets in different AZ, a NAT gateway, IGW, and specific route table
#
# DESCRIPTION
#    This shell script leverages the AWS Command Line Interface (AWS CLI) to
#    automatically create a custom VPC.  The script assumes the AWS CLI is
#    installed and configured with the necessary security credentials.
#
#==============================================================================
#
# NOTES
#   VERSION:   0.1.0
#   LASTEDIT:  10/11/2019
#   AUTHOR:    Hongliang Xiao
#   EMAIL:     xiaohongliang@outlook.com
#   REVISIONS:
#       0.1.0  10/11/2017 - first release
#       
#==============================================================================
#   MODIFY THE SETTINGS BELOW
#==============================================================================
#

AWS_REGION="us-east-2"
VPC_NAME="My Test VPC"
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR_F="10.0."
SUBNET_CIDR_R=".0/24"
SUBNET_AZ_F="us-east-2"

#
#==============================================================================
#   DO NOT MODIFY CODE BELOW
#==============================================================================
#

#create VPC
VPC_ID=$(aws ec2 create-vpc \
	--cidr-block $VPC_CIDR \
	--region $AWS_REGION \
	--query 'Vpc.[VpcId]' \
	--output text
	)
echo "VPC '$VPC_ID' CREATED IN REGION '$AWS_REGION'"
#create public subnet 
i=1	
for z in a b
do
	SUBNET_PUBLIC_AZ=${SUBNET_AZ_F}${z}
	SUBNET_PUBLIC_CIDR=${SUBNET_CIDR_F}$i${SUBNET_CIDR_R}
	eval "SUBNET_PUBLIC_ID_$i=\$(aws ec2 create-subnet \
		--availability-zone $SUBNET_PUBLIC_AZ \
		--vpc-id $VPC_ID \
		--cidr-block $SUBNET_PUBLIC_CIDR \
		--query 'Subnet.[SubnetId]' \
		--output text
		)"
	# eval会先扫描一遍后边的命令将变量代入到echo后边的字符串中，然后将第一次扫描的执行结果，在进行二次扫描，注意\$就是为了再造echo命令
	eval echo "PUBLIC SUBNET \$SUBNET_PUBLIC_ID_$i"" CREATED IN VPC '$VPC_ID'"

	eval "aws ec2 modify-subnet-attribute \
  		--subnet-id \$SUBNET_PUBLIC_ID_$i \
  		--map-public-ip-on-launch "
  	eval echo "Auto-assign Publich IP ENABLED on Public Subnet \$SUBNET_PUBLIC_ID_$i"

	i=`expr $i + 1`
done
# create private subnet
i=10
for z in a b
do
	SUBNET_PRIVATE_AZ=${SUBNET_AZ_F}${z}
	SUBNET_PUBLIC_CIDR=${SUBNET_CIDR_F}$i${SUBNET_CIDR_R}
	eval "SUBNET_PRIVATE_ID_$i=\$(aws ec2 create-subnet \
		--availability-zone $SUBNET_PUBLIC_AZ \
		--vpc-id $VPC_ID \
		--cidr-block $SUBNET_PUBLIC_CIDR \
		--query 'Subnet.[SubnetId]' \
		--output text
		)"
	# eval会先扫描一遍后边的命令将变量代入到echo后边的字符串中，然后将第一次扫描的执行结果，在进行二次扫描，注意\$就是为了再造echo命令
	eval echo "PRIVATE SUBNET \$SUBNET_PRIVATE_ID_$i"" CREATED IN VPC '$VPC_ID'"
	i=`expr $i + 10`
done

#create igw and attach
IGW_ID=$(aws ec2 create-internet-gateway \
	--query 'InternetGateway.[InternetGatewayId]' \
	--output text
	)
echo "IGW '$IGW_ID' CREATED"
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
echo "IGW '$IGW_ID' have attached to VPC '$VPC_ID'"

# create EIP
EIP_ALLOC_ID=$(aws ec2 allocate-address --domain "vpc" \
	--query 'AllocationId' \
	--output text
	)
echo "EIP '$EIP_ALLOC_ID' have allocated"

# create NAT gw
NATGW_ID=$(aws ec2 create-nat-gateway \
	--subnet-id $SUBNET_PUBLIC_ID_1 \
	--allocation-id $EIP_ALLOC_ID \
	--query 'NatGateway.NatGatewayId' \
	--output text
	)
echo "NAT GW $NATGW_ID created, please wait a moment to be active"
NATGW_STATE=$(aws ec2 describe-nat-gateways \
	--nat-gateway-ids $NATGW_ID \
	--query 'NatGateways[*].[State]' \
	--output text
	)
echo "NAT GW $NATGW_ID state is: $NATGW_STATE"
# 逻辑运算符两端要有空格，切记
# 赋值=两端不要有空格，切记
# 等待状态变为available
until [[ $NATGW_STATE == 'available' ]]; do
	sleep 5
	echo -e "waiting NATGW $NATGW_ID to be AVAILABLE \r"
	NATGW_STATE=$(aws ec2 describe-nat-gateways \
	--nat-gateway-ids $NATGW_ID \
	--query 'NatGateways[*].[State]' \
	--output text
	)
done
echo "NAT GW '$NATGW_ID' is AVAILABLE now"

# create route table to public and private subnet
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
	--vpc-id $VPC_ID \
	--query 'RouteTable.RouteTableId' \
	--output text
	)
echo "Route table $ROUTE_TABLE_ID created"

RESULT=$(aws ec2 create-route \
	--route-table-id $ROUTE_TABLE_ID \
	--destination-cidr-block 0.0.0.0/0 \
	--gateway-id $IGW_ID
	)
echo "Route to '0.0.0.0/0' via IGW '$IGW_ID' add to route table '$ROUTE_TABLE_ID'"

for SUBNET_PUBLIC_ID in $SUBNET_PUBLIC_ID_1 $SUBNET_PUBLIC_ID_2;do
	RESAULT=$(aws ec2 associate-route-table  \
		--subnet-id $SUBNET_PUBLIC_ID \
		--route-table-id $ROUTE_TABLE_ID
		)
	echo "Public Subnet ID '$SUBNET_PUBLIC_ID' ASSOCIATED with Route Table '$ROUTE_TABLE_ID'"
done

MAIN_ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
	--filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=true" \
	--query 'RouteTables[0].RouteTableId' \
	--output text
	)

RESULT=$(aws ec2 create-route \
	--route-table-id $MAIN_ROUTE_TABLE_ID \
	--destination-cidr-block 0.0.0.0/0 \
	--gateway-id $NATGW_ID
	)
echo "Route to '0.0.0.0/0' via NATGW '$NATGW_ID' add to main route table '$MAIN_ROUTE_TABLE_ID'"

echo "COMPLETED!!! Enjoy!!!"


