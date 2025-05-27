// This file is part of MinIO Console Server
// Copyright (c) 2021 MinIO, Inc.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import React, { Fragment, useEffect, useState } from "react";
import styled from "styled-components";
import { useNavigate } from "react-router-dom";
import api from "../../common/api";
import { baseUrl } from "../../history";
import { Box, Button, LoginWrapper, WarnIcon } from "mds";
import { getLogoApplicationVariant, getLogoVar } from "../../config";
import get from "lodash/get";

const CallBackContainer = styled.div(({ theme }) => ({
  "& .errorDescription": {
    fontStyle: "italic",
    transition: "all .2s ease-in-out",
    padding: "0 15px",
    marginTop: 5,
    overflow: "auto",
  },
  "& .errorLabel": {
    color: get(theme, "fontColor", "#000"),
    fontSize: 18,
    fontWeight: "bold",
    marginLeft: 5,
  },
  "& .simpleError": {
    marginTop: 5,
    padding: "2px 5px",
    fontSize: 16,
    color: get(theme, "fontColor", "#000"),
  },
  "& .messageIcon": {
    color: get(theme, "signalColors.danger", "#C72C48"),
    display: "flex",
    "& svg": {
      width: 32,
      height: 32,
    },
  },
  "& .errorTitle": {
    display: "flex",
    alignItems: "center",
    borderBottom: 15,
  },
}));

const LoginCallback = () => {
  const navigate = useNavigate();

  const [error, setError] = useState<string>("");
  const [errorDescription, setErrorDescription] = useState<string>("");
  const [loading, setLoading] = useState<boolean>(true);

  useEffect(() => {
    if (loading) {
      const queryString = window.location.search;
      const urlParams = new URLSearchParams(queryString);
      const code = urlParams.get("code");
      const state = urlParams.get("state");
      const error = urlParams.get("error");
      const errorDescription = urlParams.get("errorDescription");
      if (error || errorDescription) {
        setError(error || "");
        setErrorDescription(errorDescription || "");
        setLoading(false);
      } else {
        api
          .invoke("POST", "/api/v1/login/oauth2/auth", { code, state })
          .then(() => {
            // We push to history the new URL.
            let targetPath = "/";
            if (
              localStorage.getItem("redirect-path") &&
              localStorage.getItem("redirect-path") !== ""
            ) {
              targetPath = `${localStorage.getItem("redirect-path")}`;
              localStorage.setItem("redirect-path", "");
            }
            if (state) {
              localStorage.setItem("auth-state", state);
            }
            setLoading(false);
            navigate(targetPath);
          })
          .catch((error) => {
            setError(error.errorMessage);
            setErrorDescription(error.detailedError);
            setLoading(false);
          });
      }
    }
  }, [loading, navigate]);
  return error !== "" || errorDescription !== "" ? (
    <Fragment>
      <LoginWrapper
        logoProps={{
          applicationName: getLogoApplicationVariant(),
          subVariant: getLogoVar(),
        }}
        form={
          <CallBackContainer>
            <div className={"errorTitle"}>
              <span className={"messageIcon"}>
                <WarnIcon />
              </span>
              <span className={"errorLabel"}>Error from IDP</span>
            </div>
            <div className={"simpleError"}>{error}</div>
            <Box className={"errorDescription"}>{errorDescription}</Box>
            <Button
              id={"back-to-login"}
              onClick={() => {
                window.location.href = `${baseUrl}login`;
              }}
              type="submit"
              variant="callAction"
              fullWidth
            >
              Back to Login
            </Button>
          </CallBackContainer>
        }
        promoHeader={
          <span style={{ fontSize: 28 }}>High-Performance Object Store</span>
        }
        promoInfo={
          <span style={{ fontSize: 14, lineHeight: 1 }}>
            OpenMaxIO is a cloud-native object store built to run on any
            infrastructure - public, private or edge clouds. Primary use cases
            include data lakes, databases, AI/ML, SaaS applications and fast
            backup & recovery. MinIO is dual licensed under GNU AGPL v3 and
            commercial license. To learn more, visit{" "}
            <a href={"https://min.io/?ref=con"} target="_blank" rel="noopener">
              www.min.io
            </a>
            .
          </span>
        }
        backgroundAnimation={false}
      />
    </Fragment>
  ) : null;
};

export default LoginCallback;
